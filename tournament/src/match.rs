
use super::{build_machine_id, build_session_run_key};
use super::configuration::Concern;
use super::dispatcher::{AddressField, AddressArray3, U256Array4, Bytes32Field, Bytes32Array3, String32Field, U256Field};
use super::dispatcher::{Archive, DApp, Reaction};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use super::transaction;
use super::transaction::TransactionRequest;
use super::{cartesi_base, Role, VG, SessionRunRequest, SessionRunResult,
    NewSessionRequest, NewSessionResult, 
    EMULATOR_SERVICE_NAME, EMULATOR_METHOD_RUN, EMULATOR_METHOD_NEW,
    Hash, FilePath, LOGGER_SERVICE_NAME, LOGGER_METHOD_DOWNLOAD};
use super::{VGCtx, VGCtxParsed};

use std::time::{SystemTime, UNIX_EPOCH};

pub struct Match();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
pub struct MatchCtxParsed(
    AddressArray3, // challenger
                   // claimer
                   // machine
    U256Array4,    // epochNumber
                   // roundDuration
                   // timeOfLastMove
                   // finalTime
    Bytes32Array3, // logHash
                   // initialHash
                   // finalHash
    String32Field, // currentState
);

#[derive(Serialize, Debug)]
pub struct MatchCtx {
    pub challenger: Address,
    pub claimer: Address,
    pub machine: Address,
    pub epoch_number: U256,
    pub round_duration: U256,
    pub time_of_last_move: U256,
    pub log_hash: H256,
    pub initial_hash: H256,
    pub claimed_final_hash: H256,
    pub final_time: U256,
    pub current_state: String,
}

#[derive(Default)]
pub struct MachineTemplate {
    pub machine: cartesi_base::MachineRequest,
    pub drive_index: usize
}

impl From<MatchCtxParsed> for MatchCtx {
    fn from(parsed: MatchCtxParsed) -> MatchCtx {
        MatchCtx {
            challenger: parsed.0.value[0],
            claimer: parsed.0.value[1],
            machine: parsed.0.value[2],
            epoch_number: parsed.1.value[0],
            round_duration: parsed.1.value[1],
            time_of_last_move: parsed.1.value[2],
            final_time: parsed.1.value[3],
            log_hash: parsed.2.value[0],
            initial_hash: parsed.2.value[1],
            claimed_final_hash: parsed.2.value[2],
            current_state: parsed.3.value,
        }
    }
}

impl DApp<MachineTemplate> for Match {
    /// React to the Match contract, submitting solutions, confirming
    /// or challenging them when appropriate
    fn react(
        instance: &state::Instance,
        archive: &Archive,
        post_payload: &Option<String>,
        machine_template: &MachineTemplate,
    ) -> Result<Reaction> {
        // get context (state) of the match instance
        let parsed: MatchCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse match instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: MatchCtx = parsed.into();
        trace!("Context for match (index {}) {:?}", instance.index, ctx);

        // these states should not occur as they indicate an innactive instance,
        // but it is possible that the blockchain state changed between queries
        match ctx.current_state.as_ref() {
            "ChallengerWon"
            | "ClaimerWon" => {
                return Ok(Reaction::Idle);
            }
            _ => {}
        };

        // if we reach this code, the instance is active, get user's role
        let role = match instance.concern.user_address {
            cl if (cl == ctx.claimer) => Role::Claimer,
            ch if (ch == ctx.challenger) => Role::Challenger,
            _ => {
                return Err(Error::from(ErrorKind::InvalidContractState(
                    String::from("User is neither claimer nor challenger"),
                )));
            }
        };
        trace!("Role played (index {}) is: {:?}", instance.index, role);

        match role {
            Role::Claimer => match ctx.current_state.as_ref() {
                "WaitingChallenge" => {
                    return win_by_deadline_or_idle(
                        &instance.concern,
                        instance.index,
                        ctx.time_of_last_move.as_u64(),
                        ctx.round_duration.as_u64(),
                    );
                }

                "ChallengeStarted" => {
                    // we inspect the verification contract
                    let vg_instance = instance.sub_instances.get(0).ok_or(
                        Error::from(ErrorKind::InvalidContractState(format!(
                            "There is no vg instance {}",
                            ctx.current_state
                        ))),
                    )?;
                    let vg_parsed: VGCtxParsed =
                        serde_json::from_str(&vg_instance.json_data)
                            .chain_err(|| {
                                format!(
                                    "Could not parse vg instance json_data: {}",
                                    &vg_instance.json_data
                                )
                            })?;
                    let vg_ctx: VGCtx = vg_parsed.into();

                    match vg_ctx.current_state.as_ref() {
                        "FinishedClaimerWon" => {
                            // claim victory in compute contract
                            let request = TransactionRequest {
                                concern: instance.concern.clone(),
                                value: U256::from(0),
                                function: "winByVG".into(),
                                data: vec![Token::Uint(instance.index)],
                                strategy: transaction::Strategy::Simplest,
                            };
                            return Ok(Reaction::Transaction(request));
                        }
                        "FinishedChallengerWon" => {
                            error!("we lost a verification game {:?}", vg_ctx);
                            return Ok(Reaction::Idle);
                        }
                        _ => {
                            // verification game is still active,
                            // pass control to the appropriate dapp
                            return VG::react(vg_instance, archive, &None, &());
                        }
                    }
                }
                _ => {
                    return Err(Error::from(ErrorKind::InvalidContractState(
                        format!("Unknown current state {}", ctx.current_state),
                    )));
                }
            },
            Role::Challenger => match ctx.current_state.as_ref() {
                "WaitingChallenge" => {
                    // download the log of the opponent with given hash
                    trace!("Download file for hash: {:?}...", ctx.log_hash);

                    let request = Hash {
                        hash: ctx.log_hash.clone()
                    };

                    let processed_response: FilePath = archive.get_response(
                        LOGGER_SERVICE_NAME.to_string(),
                        format!("{:x}", ctx.log_hash.clone()),
                        LOGGER_METHOD_DOWNLOAD.to_string(),
                        request.into())?
                        .map_err(|_| {
                            Error::from(ErrorKind::ArchiveInvalidError(
                                LOGGER_SERVICE_NAME.to_string(),
                                format!("{:x}", ctx.log_hash.clone()),
                                LOGGER_METHOD_DOWNLOAD.to_string()))
                        })?
                        .into();
                    trace!("Downloaded! File stored at: {}...", processed_response.path);

                    // machine id
                    let id = build_machine_id(
                        instance.index,
                        &instance.concern.contract_address,
                    );

                    // TODO: replace one drive in the machine struct

                    let request = NewSessionRequest {
                        session_id: id.clone(),
                        machine: machine_template.machine.clone()
                    };
                    // send newSession request to the emulator service

                    let id_clone = id.clone();
                    let duplicate_session_msg = format!("Trying to register a session with a session_id that already exists: {}", id);
                    let _processed_response: NewSessionResult = archive.get_response(
                        EMULATOR_SERVICE_NAME.to_string(),
                        id.clone(),
                        EMULATOR_METHOD_NEW.to_string(),
                        request.into())?
                        .map_err(move |e| {
                            if e == duplicate_session_msg {
                                Error::from(ErrorKind::ArchiveNeedsDummy(
                                    EMULATOR_SERVICE_NAME.to_string(),
                                    id_clone,
                                    EMULATOR_METHOD_NEW.to_string()))
                            } else {
                                Error::from(ErrorKind::ArchiveInvalidError(
                                    EMULATOR_SERVICE_NAME.to_string(),
                                    id_clone,
                                    EMULATOR_METHOD_NEW.to_string()))
                            }
                        })?
                        .into();

                    // here goes the calculation of the final hash
                    // to check the claim and potentialy raise challenge
                    let sample_points: Vec<u64> =
                        vec![0, ctx.final_time.as_u64()];
                    let request = SessionRunRequest {
                        session_id: id.clone(),
                        times: sample_points.clone(),
                    };
                    let archive_key = build_session_run_key(
                        id.clone(),
                        sample_points.clone());
                    let id_clone = id.clone();

                    trace!("Calculating final hash of machine {}", id);
                    // have we sampled the final time?
                    let processed_response: SessionRunResult = archive.get_response(
                        EMULATOR_SERVICE_NAME.to_string(),
                        archive_key.clone(),
                        EMULATOR_METHOD_RUN.to_string(),
                        request.into())?
                        .map_err(move |_e| {
                            Error::from(ErrorKind::ArchiveInvalidError(
                                EMULATOR_SERVICE_NAME.to_string(),
                                id_clone,
                                EMULATOR_METHOD_RUN.to_string()))
                        })?
                        .into();

                    let hash = processed_response.hashes[1];
                    if hash == ctx.claimed_final_hash {
                        info!(
                            "Confirming final hash {:?} for {}",
                            hash, id
                        );
                        return Ok(Reaction::Idle);
                    } else {
                        warn!(
                            "Disputing final hash {:?} != {} for {}",
                            hash, ctx.claimed_final_hash, id
                        );
                        let request = TransactionRequest {
                            concern: instance.concern.clone(),
                            value: U256::from(0),
                            function: "challengeHighestScore".into(),
                            data: vec![Token::Uint(instance.index)],
                            strategy: transaction::Strategy::Simplest,
                        };

                        return Ok(Reaction::Transaction(request));
                    }
                }
                "ChallengeStarted" => {
                    // we inspect the verification contract
                    let vg_instance = instance.sub_instances.get(0).ok_or(
                        Error::from(ErrorKind::InvalidContractState(format!(
                            "There is no vg instance {}",
                            ctx.current_state
                        ))),
                    )?;
                    let vg_parsed: VGCtxParsed =
                        serde_json::from_str(&vg_instance.json_data)
                            .chain_err(|| {
                                format!(
                                    "Could not parse vg instance json_data: {}",
                                    &vg_instance.json_data
                                )
                            })?;
                    let vg_ctx: VGCtx = vg_parsed.into();

                    match vg_ctx.current_state.as_ref() {
                        "FinishedChallengerWon" => {
                            // claim victory in compute contract
                            let request = TransactionRequest {
                                concern: instance.concern.clone(),
                                value: U256::from(0),
                                function: "winByVG".into(),
                                data: vec![Token::Uint(instance.index)],
                                strategy: transaction::Strategy::Simplest,
                            };
                            return Ok(Reaction::Transaction(request));
                        }
                        "FinishedClaimerWon" => {
                            error!("we lost a verification game {:?}", vg_ctx);
                            return Ok(Reaction::Idle);
                        }
                        _ => {
                            // verification game is still active,
                            // pass control to the appropriate dapp
                            return VG::react(vg_instance, archive, &None, &());
                        }
                    }
                }
                _ => {
                    return Err(Error::from(ErrorKind::InvalidContractState(
                        format!("Unknown current state {}", ctx.current_state),
                    )));
                }
            },
        }
    }

    fn get_pretty_instance(
        instance: &state::Instance,
        archive: &Archive,
        _: &MachineTemplate,
    ) -> Result<state::Instance> {

        // get context (state) of the match instance
        let parsed: MatchCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse match instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: MatchCtx = parsed.into();
        let json_data = serde_json::to_string(&ctx).unwrap();

        // get context (state) of the sub instances

        let mut pretty_sub_instances : Vec<Box<state::Instance>> = vec![];

        for sub in &instance.sub_instances {
            pretty_sub_instances.push(
                Box::new(
                    VG::get_pretty_instance(
                        sub,
                        archive,
                        &(),
                    )
                    .unwrap()
                )
            )
        }

        let pretty_instance = state::Instance {
            name: "Match".to_string(),
            concern: instance.concern.clone(),
            index: instance.index,
            json_data: json_data,
            sub_instances: pretty_sub_instances,
        };

        return Ok(pretty_instance)
    }
}

pub fn win_by_deadline_or_idle(
    concern: &Concern,
    index: U256,
    time_of_last_move: u64,
    round_duration: u64,
) -> Result<Reaction> {
    let current_time = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .chain_err(|| "System time before UNIX_EPOCH")?
        .as_secs();

    // if other party missed the deadline
    if current_time > time_of_last_move + round_duration {
        let request = TransactionRequest {
            concern: concern.clone(),
            value: U256::from(0),
            function: "claimVictoryByTime".into(),
            data: vec![Token::Uint(index)],
            strategy: transaction::Strategy::Simplest,
        };
        return Ok(Reaction::Transaction(request));
    } else {
        // if not, then wait
        return Ok(Reaction::Idle);
    }
}
