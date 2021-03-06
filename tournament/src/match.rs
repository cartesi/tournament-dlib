// Copyright (C) 2020 Cartesi Pte. Ltd.

// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.

// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Note: This component currently has dependencies that are licensed under the GNU
// GPL, version 3, and so you should treat this component as a whole as being under
// the GPL version 3. But all Cartesi-written code in this component is licensed
// under the Apache License, version 2, or a compatible permissive license, and can
// be used independently under the Apache v2 license. After this component is
// rewritten, the entire component will be released under the Apache v2 license.

use super::configuration::Concern;
use super::dispatcher::{AddressArray3, Bytes32Array3, String32Field, U256Array3};
use super::dispatcher::{Archive, DApp, Reaction};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use super::transaction;
use super::transaction::TransactionRequest;
use super::{build_machine_id, build_session_run_key};
use super::{
    cartesi_base, DownloadFileRequest, DownloadFileResponse, NewSessionRequest, NewSessionResult, Role,
    SessionRunRequest, SessionRunResult, EMULATOR_METHOD_NEW, EMULATOR_METHOD_RUN,
    EMULATOR_SERVICE_NAME, LOGGER_METHOD_DOWNLOAD, LOGGER_SERVICE_NAME, VG, get_logger_response
};
use super::{VGCtx, VGCtxParsed, win_by_deadline_or_idle};

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
    U256Array3, // epochNumber
    // deadline
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
    pub deadline: U256,
    pub log_hash: H256,
    pub initial_hash: H256,
    pub claimed_final_hash: H256,
    pub final_time: U256,
    pub current_state: String,
}

#[derive(Default)]
pub struct MachineTemplate {
    pub machine: cartesi_base::MachineRequest,
    pub opponent_machine: cartesi_base::MachineRequest,
    pub tournament_index: U256,
    pub page_log2_size: u64,
    pub tree_log2_size: u64,
    pub final_time: u64,
}

impl From<MatchCtxParsed> for MatchCtx {
    fn from(parsed: MatchCtxParsed) -> MatchCtx {
        MatchCtx {
            challenger: parsed.0.value[0],
            claimer: parsed.0.value[1],
            machine: parsed.0.value[2],
            epoch_number: parsed.1.value[0],
            deadline: parsed.1.value[1],
            final_time: parsed.1.value[2],
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
        _post_payload: &Option<String>,
        machine_template: &MachineTemplate,
    ) -> Result<Reaction> {
        // get context (state) of the match instance
        let parsed: MatchCtxParsed = serde_json::from_str(&instance.json_data).chain_err(|| {
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
            "ChallengerWon" | "ClaimerWon" => {
                return Ok(Reaction::Idle);
            }
            _ => {}
        };

        // if we reach this code, the instance is active, get user's role
        let role = match instance.concern.user_address {
            cl if (cl == ctx.claimer) => Role::Claimer,
            ch if (ch == ctx.challenger) => Role::Challenger,
            _ => {
                return Err(Error::from(ErrorKind::InvalidContractState(String::from(
                    "User is neither claimer nor challenger",
                ))));
            }
        };
        trace!("Role played (index {}) is: {:?}", instance.index, role);

        match role {
            Role::Claimer => match ctx.current_state.as_ref() {
                "WaitingChallenge" => {
                    return win_by_deadline_or_idle(
                        &instance.concern,
                        instance.index,
                        ctx.deadline.as_u64(),
                    );
                }

                "ChallengeStarted" => {
                    // we inspect the verification contract
                    let vg_instance = instance.sub_instances.get(0).ok_or(Error::from(
                        ErrorKind::InvalidContractState(format!(
                            "There is no vg instance {}",
                            ctx.current_state
                        )),
                    ))?;
                    let vg_parsed: VGCtxParsed = serde_json::from_str(&vg_instance.json_data)
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
                            info!("Claiming victory by VG (index: {})", instance.index);
                            let request = TransactionRequest {
                                concern: instance.concern.clone(),
                                value: U256::from(0),
                                function: "winByVG".into(),
                                data: vec![Token::Uint(instance.index)],
                                gas: None,
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
                            let id =
                                build_machine_id(machine_template.tournament_index, &ctx.claimer);
                            return VG::react(vg_instance, archive, &None, &id);
                        }
                    }
                }
                _ => {
                    return Err(Error::from(ErrorKind::InvalidContractState(format!(
                        "Unknown current state {}",
                        ctx.current_state
                    ))));
                }
            },
            Role::Challenger => match ctx.current_state.as_ref() {
                "WaitingChallenge" => {
                    // download the log of the opponent with given hash
                    trace!("Download file for hash: {:?}...", ctx.log_hash);

                    let request = DownloadFileRequest {
                        root: ctx.log_hash.clone(),
                        path: format!("{}_opponent.json.br.cpio", machine_template.tournament_index),
                        page_log2_size: machine_template.page_log2_size,
                        tree_log2_size: machine_template.tree_log2_size,
                    };

                    let processed_response: DownloadFileResponse = get_logger_response(
                            archive,
                            "Match".into(),
                            LOGGER_SERVICE_NAME.to_string(),
                            format!("{:x}", ctx.log_hash.clone()),
                            LOGGER_METHOD_DOWNLOAD.to_string(),
                            request.into(),
                        )?
                        .into();
                    trace!("Downloaded! File stored at: {}...", processed_response.path);

                    // machine id
                    let id = build_machine_id(machine_template.tournament_index, &ctx.claimer);

                    let request = NewSessionRequest {
                        session_id: id.clone(),
                        machine: machine_template.opponent_machine.clone(),
                    };

                    // send newSession request to the emulator service
                    let id_clone = id.clone();
                    let duplicate_session_msg = format!(
                        "Trying to register a session with a session_id that already exists: {}",
                        id
                    );
                    let _processed_response: NewSessionResult = archive
                        .get_response(
                            EMULATOR_SERVICE_NAME.to_string(),
                            id.clone(),
                            EMULATOR_METHOD_NEW.to_string(),
                            request.into(),
                        )?
                        .map_err(move |e| {
                            if e == duplicate_session_msg {
                                Error::from(ErrorKind::ResponseNeedsDummy(
                                    EMULATOR_SERVICE_NAME.to_string(),
                                    id_clone,
                                    EMULATOR_METHOD_NEW.to_string(),
                                ))
                            } else {
                                Error::from(ErrorKind::ResponseInvalidError(
                                    EMULATOR_SERVICE_NAME.to_string(),
                                    id_clone,
                                    EMULATOR_METHOD_NEW.to_string(),
                                ))
                            }
                        })?
                        .into();

                    // here goes the calculation of the final hash
                    // to check the claim and potentialy raise challenge
                    let sample_points: Vec<u64> = vec![0, ctx.final_time.as_u64()];
                    let request = SessionRunRequest {
                        session_id: id.clone(),
                        times: sample_points.clone(),
                    };
                    let archive_key = build_session_run_key(id.clone(), sample_points.clone());

                    trace!("Calculating final hash of machine {}", id);
                    // have we sampled the final time?
                    let processed_response: SessionRunResult = archive
                        .get_response(
                            EMULATOR_SERVICE_NAME.to_string(),
                            archive_key.clone(),
                            EMULATOR_METHOD_RUN.to_string(),
                            request.into(),
                        )?
                        .map_err(move |_e| {
                            Error::from(ErrorKind::ResponseInvalidError(
                                EMULATOR_SERVICE_NAME.to_string(),
                                archive_key,
                                EMULATOR_METHOD_RUN.to_string(),
                            ))
                        })?
                        .into();

                    let hash = processed_response.hashes[1];
                    if hash == ctx.claimed_final_hash {
                        info!("Confirming final hash {:?} for {}", hash, id);
                        return Ok(Reaction::Idle);
                    } else {
                        info!(
                            "Disputing final hash {:?} != {} for {}",
                            hash, ctx.claimed_final_hash, id
                        );
                        let request = TransactionRequest {
                            concern: instance.concern.clone(),
                            value: U256::from(0),
                            function: "challengeHighestScore".into(),
                            data: vec![Token::Uint(instance.index)],
                            gas: None,
                            strategy: transaction::Strategy::Simplest,
                        };

                        return Ok(Reaction::Transaction(request));
                    }
                }
                "ChallengeStarted" => {
                    // we inspect the verification contract
                    let vg_instance = instance.sub_instances.get(0).ok_or(Error::from(
                        ErrorKind::InvalidContractState(format!(
                            "There is no vg instance {}",
                            ctx.current_state
                        )),
                    ))?;
                    let vg_parsed: VGCtxParsed = serde_json::from_str(&vg_instance.json_data)
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
                            info!("Claiming victory by VG (index: {})", instance.index);
                            let request = TransactionRequest {
                                concern: instance.concern.clone(),
                                value: U256::from(0),
                                function: "winByVG".into(),
                                data: vec![Token::Uint(instance.index)],
                                gas: None,
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
                            let id =
                                build_machine_id(machine_template.tournament_index, &ctx.claimer);
                            return VG::react(vg_instance, archive, &None, &id);
                        }
                    }
                }
                _ => {
                    return Err(Error::from(ErrorKind::InvalidContractState(format!(
                        "Unknown current state {}",
                        ctx.current_state
                    ))));
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
        let parsed: MatchCtxParsed = serde_json::from_str(&instance.json_data).chain_err(|| {
            format!(
                "Could not parse match instance json_data: {}",
                &instance.json_data
            )
        })?;
        let ctx: MatchCtx = parsed.into();
        let json_data = serde_json::to_string(&ctx).unwrap();

        // get context (state) of the sub instances

        let mut pretty_sub_instances: Vec<Box<state::Instance>> = vec![];

        for sub in &instance.sub_instances {
            pretty_sub_instances.push(Box::new(
                VG::get_pretty_instance(sub, archive, &"".to_string()).unwrap(),
            ))
        }

        let pretty_instance = state::Instance {
            name: "Match".to_string(),
            concern: instance.concern.clone(),
            index: instance.index,
            service_status: archive.get_service("Match".into()),
            json_data: json_data,
            sub_instances: pretty_sub_instances,
        };

        return Ok(pretty_instance);
    }
}
