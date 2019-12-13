use super::configuration::Concern;
use super::dispatcher::{Archive, DApp, Reaction};
use super::dispatcher::{BoolField, Bytes32Field, String32Field, U256Array6};
use super::error::Result;
use super::error::*;
use super::hex;
use super::ethabi::Token;
use super::ethereum_types::{H256, U256};
use super::transaction;
use super::transaction::TransactionRequest;
use super::{
    build_machine_id, build_session_proof_key, build_session_read_key, build_session_run_key,
};
use super::{
    cartesi_base, Hash, NewSessionRequest, NewSessionResult, SessionGetProofRequest,
    SessionGetProofResult, SessionReadMemoryRequest, SessionReadMemoryResult, SessionRunRequest,
    SessionRunResult, SubmitFileRequest, EMULATOR_METHOD_NEW, EMULATOR_METHOD_PROOF,
    EMULATOR_METHOD_READ, EMULATOR_METHOD_RUN, EMULATOR_SERVICE_NAME, LOGGER_METHOD_SUBMIT,
    LOGGER_SERVICE_NAME,
};

use super::crypto::digest::Digest;
use super::crypto::sha3::Sha3;
use r#match::MachineTemplate;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct RevealCommit();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
pub struct RevealCommitCtxParsed(
    pub U256Array6, // instantiatedAt
    // commitDuration
    // revealDuration
    // scoreWordPosition
    // logDrivePosition
    // logDriveLogSize
    pub Bytes32Field,  // logHash;
    pub BoolField,     // hasRevealed
    pub BoolField,     // logAvailable
    pub String32Field, // currentState
);

#[derive(Serialize, Debug)]
pub struct RevealCommitCtx {
    pub instantiated_at: U256,
    pub commit_duration: U256,
    pub reveal_duration: U256,
    pub score_word_position: U256,
    pub log_drive_position: U256,
    pub log_drive_log_size: U256,

    pub log_hash: H256,

    pub has_revealed: bool,
    pub log_available: bool,

    pub current_state: String,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Payload {
    pub action: String,
    pub params: Params,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Params {
    pub hash: H256,
}

fn to_bytes(input: Vec<u8>) -> Option<[u8; 8]> {
    if input.len() != 8 {
        None
    } else {
        Some([
            input[0], input[1], input[2], input[3], input[4], input[5], input[6], input[7],
        ])
    }
}
impl From<RevealCommitCtxParsed> for RevealCommitCtx {
    fn from(parsed: RevealCommitCtxParsed) -> RevealCommitCtx {
        RevealCommitCtx {
            instantiated_at: parsed.0.value[0],
            commit_duration: parsed.0.value[1],
            reveal_duration: parsed.0.value[2],
            score_word_position: parsed.0.value[3],
            log_drive_position: parsed.0.value[4],
            log_drive_log_size: parsed.0.value[5],

            log_hash: parsed.1.value,

            has_revealed: parsed.2.value,
            log_available: parsed.3.value,

            current_state: parsed.4.value,
        }
    }
}

impl DApp<(MachineTemplate)> for RevealCommit {
    /// React to the Reveal contract
    fn react(
        instance: &state::Instance,
        archive: &Archive,
        post_payload: &Option<String>,
        machine_template: &MachineTemplate,
    ) -> Result<Reaction> {
        // get context (state) of the reveal instance
        let parsed: RevealCommitCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse reveal instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: RevealCommitCtx = parsed.into();
        trace!(
            "Context for reveal_commit (index {}) {:?}",
            instance.index,
            ctx
        );

        let current_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .chain_err(|| "System time before UNIX_EPOCH")?
            .as_secs();

        match ctx.current_state.as_ref() {
            "CommitRevealDone" => {
                // if commit and reveal is done, nothing to do here.
                return Ok(Reaction::Idle);
            }

            "CommitPhase" => {
                match post_payload {
                    // if post_payload is not empty, commit
                    Some(s) => {
                        let payload: Payload = serde_json::from_str(&s)
                            .chain_err(|| format!("Could not parse post_payload: {}", &s))?;

                        // concatenate log_hash with user address
                        let mut hash_data: [u8; 52] = [0; 52];
                        payload.params.hash.copy_to(&mut hash_data[0..32]);
                        instance.concern.user_address.copy_to(&mut hash_data[32..52]);

                        // get keccak256 of that string
                        let mut hasher = Sha3::keccak256();
                        hasher.input(&hash_data);
                        let commit_hash = hasher.result_str();

                        let request = TransactionRequest {
                            concern: instance.concern.clone(),
                            value: U256::from(0),
                            function: "commit".into(),
                            // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                            // improve these types by letting the
                            // dapp submit ethereum_types and convert
                            // them inside the transaction manager
                            // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                            data: vec![
                                Token::Uint(instance.index),
                                Token::FixedBytes(hex::decode(commit_hash).expect("Decoding failed")),
                            ],
                            strategy: transaction::Strategy::Simplest,
                        };
                        return Ok(Reaction::Transaction(request));
                    }
                    None => {
                        let phase_is_over = current_time
                            > ctx.instantiated_at.as_u64() + ctx.commit_duration.as_u64();

                        if phase_is_over {
                            // if commit phase is over, player reveal his log and forces the phase change
                            return complete_reveal_phase(
                                &instance.concern,
                                instance.index,
                                archive,
                                ctx.log_hash,
                                machine_template,
                            );
                        }
                        // If there is no post and the phase is not over, idles
                        return Ok(Reaction::Idle);
                    }
                }
            }

            "RevealPhase" => {
                let phase_is_over = current_time
                    > ctx.instantiated_at.as_u64()
                        + ctx.commit_duration.as_u64()
                        + ctx.reveal_duration.as_u64();

                if phase_is_over && ctx.has_revealed {
                    // TO-DO: Fix race condition / lack of incentive for calling it
                    let request = TransactionRequest {
                        concern: instance.concern.clone(),
                        value: U256::from(0),
                        function: "endCommitAndReveal".into(),
                        data: vec![Token::Uint(instance.index)],
                        strategy: transaction::Strategy::Simplest,
                    };

                    return Ok(Reaction::Transaction(request));
                }

                // if has player has revealed but phase is not over, return idle
                if ctx.has_revealed {
                    return Ok(Reaction::Idle);
                }

                // else complete reveal
                return complete_reveal_phase(
                    &instance.concern,
                    instance.index,
                    archive,
                    ctx.log_hash,
                    machine_template,
                );
            }

            _ => {
                return Ok(Reaction::Idle);
            }
        }
    }

    fn get_pretty_instance(
        instance: &state::Instance,
        _archive: &Archive,
        _: &MachineTemplate,
    ) -> Result<state::Instance> {
        // get context (state) of the match instance
        let parsed: RevealCommitCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse match instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: RevealCommitCtx = parsed.into();
        let json_data = serde_json::to_string(&ctx).unwrap();

        let pretty_sub_instances: Vec<Box<state::Instance>> = vec![];

        let pretty_instance = state::Instance {
            name: "RevealCommit".to_string(),
            concern: instance.concern.clone(),
            index: instance.index,
            json_data: json_data,
            sub_instances: pretty_sub_instances,
        };

        return Ok(pretty_instance);
    }
}

pub fn complete_reveal_phase(
    concern: &Concern,
    index: U256,
    archive: &Archive,
    log_hash: H256,
    machine_template: &MachineTemplate,
) -> Result<Reaction> {
    // automatically submitting the log to the logger
    let path = format!("{}.json.br.tar", machine_template.tournament_index);
    trace!("Submitting file: {}...", path);

    let request = SubmitFileRequest {
        path: path.clone(),
        page_log2_size: machine_template.page_log2_size,
        tree_log2_size: machine_template.tree_log2_size,
    };

    let processed_response: Hash = archive
        .get_response(
            LOGGER_SERVICE_NAME.to_string(),
            path.clone(),
            LOGGER_METHOD_SUBMIT.to_string(),
            request.into(),
        )?
        .map_err(move |_e| {
            Error::from(ErrorKind::ArchiveInvalidError(
                LOGGER_SERVICE_NAME.to_string(),
                path,
                LOGGER_METHOD_SUBMIT.to_string(),
            ))
        })?
        .into();
    trace!("Submitted! Result: {:?}...", processed_response.hash);

    // build machine
    let id = build_machine_id(machine_template.tournament_index, &concern.user_address);

    // send newSession request to the emulator service
    let request = NewSessionRequest {
        session_id: id.clone(),
        machine: machine_template.machine.clone(),
    };
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
                Error::from(ErrorKind::ArchiveNeedsDummy(
                    EMULATOR_SERVICE_NAME.to_string(),
                    id_clone,
                    EMULATOR_METHOD_NEW.to_string(),
                ))
            } else {
                Error::from(ErrorKind::ArchiveInvalidError(
                    EMULATOR_SERVICE_NAME.to_string(),
                    id_clone,
                    EMULATOR_METHOD_NEW.to_string(),
                ))
            }
        })?
        .into();

    // Score is the first word (logsize = 3) of the output drive
    // The output drive starts at address: (1<<63)+(3<<61)
    // The score is there when the machine halts (final_time)
    let id_clone = id.clone();
    let time = machine_template.final_time;
    let address = (1 << 63) + (3 << 61);

    // TO-DO: Verify if length is in bytes!
    let length = 8;
    let score_logsize_2 = 3;

    let archive_key = build_session_read_key(id.clone(), time, address, length);
    let mut position = cartesi_base::ReadMemoryRequest::new();
    position.set_address(address);
    position.set_length(length);

    let request = SessionReadMemoryRequest {
        session_id: id.clone(),
        time: time,
        position: position,
    };

    let processed_response: SessionReadMemoryResult = archive
        .get_response(
            EMULATOR_SERVICE_NAME.to_string(),
            archive_key.clone(),
            EMULATOR_METHOD_READ.to_string(),
            request.into(),
        )?
        .map_err(move |_e| {
            Error::from(ErrorKind::ArchiveInvalidError(
                EMULATOR_SERVICE_NAME.to_string(),
                archive_key,
                EMULATOR_METHOD_READ.to_string(),
            ))
        })?
        .into();

    trace!(
        "Read memory result: {:?}...",
        processed_response.read_content.data
    );

    let score = processed_response.read_content.data;

    // get score proof (siblings)
    let id_clone = id.clone();

    let archive_key = build_session_proof_key(id.clone(), time, address, score_logsize_2);
    let mut target = cartesi_base::GetProofRequest::new();
    target.set_address(address);
    target.set_log2_size(score_logsize_2);

    let request = SessionGetProofRequest {
        session_id: id.clone(),
        time: time,
        target: target,
    };

    let processed_response: SessionGetProofResult = archive
        .get_response(
            EMULATOR_SERVICE_NAME.to_string(),
            archive_key.clone(),
            EMULATOR_METHOD_PROOF.to_string(),
            request.into(),
        )?
        .map_err(move |_e| {
            Error::from(ErrorKind::ArchiveInvalidError(
                EMULATOR_SERVICE_NAME.to_string(),
                archive_key,
                EMULATOR_METHOD_PROOF.to_string(),
            ))
        })?
        .into();

    trace!("Get proof result: {:?}...", processed_response.proof);

    // TO-DO: transform V<u8> to uint
    let score_siblings = processed_response.proof;

    // get hash of log drive from emulator
    // Log drive starts at address (1<<63)+(2<<61)
    // Log size is 1 MB
    // Siblings should be checked against template hash (time = 0)
    let id_clone = id.clone();
    let time = 0;
    let address = (1 << 63) + (2 << 61);
    let log2_size = 20; // 1MB

    let archive_key = build_session_proof_key(id.clone(), time, address, log2_size);
    let mut target = cartesi_base::GetProofRequest::new();
    target.set_address(address);
    target.set_log2_size(log2_size);

    let request = SessionGetProofRequest {
        session_id: id.clone(),
        time: time,
        target: target,
    };

    let processed_response: SessionGetProofResult = archive
        .get_response(
            EMULATOR_SERVICE_NAME.to_string(),
            archive_key.clone(),
            EMULATOR_METHOD_PROOF.to_string(),
            request.into(),
        )?
        .map_err(move |_e| {
            Error::from(ErrorKind::ArchiveInvalidError(
                EMULATOR_SERVICE_NAME.to_string(),
                archive_key,
                EMULATOR_METHOD_PROOF.to_string(),
            ))
        })?
        .into();

    trace!("Get proof result: {:?}...", processed_response.proof);

    let log_siblings = processed_response.proof;

    // TO-DO: what is final time?
    let sample_points: Vec<u64> = vec![0, machine_template.final_time];

    let request = SessionRunRequest {
        session_id: id.clone(),
        times: sample_points.clone(),
    };
    let archive_key = build_session_run_key(id.clone(), sample_points.clone());
    let id_clone = id.clone();

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
            Error::from(ErrorKind::ArchiveInvalidError(
                EMULATOR_SERVICE_NAME.to_string(),
                archive_key,
                EMULATOR_METHOD_RUN.to_string(),
            ))
        })?
        .into();

    let final_hash = processed_response.hashes[1];

    // get actual siblings
    let mut log_siblings: Vec<_> = log_siblings
        .sibling_hashes
        .into_iter()
        .map(|hash| Token::FixedBytes(hash.0.to_vec()))
        .collect();
    trace!("Size of siblings: {}", log_siblings.len());
    // !!!!! This should not be necessary, !!!!!!!
    // !!!!! the emulator should do it     !!!!!!!
    log_siblings.reverse();

    // get actual siblings
    let mut score_siblings: Vec<_> = score_siblings
        .sibling_hashes
        .into_iter()
        .map(|hash| Token::FixedBytes(hash.0.to_vec()))
        .collect();
    trace!("Size of siblings: {}", score_siblings.len());
    // !!!!! This should not be necessary, !!!!!!!
    // !!!!! the emulator should do it     !!!!!!!
    score_siblings.reverse();

    let request = TransactionRequest {
        concern: concern.clone(),
        value: U256::from(0),
        function: "reveal".into(),
        data: vec![
            Token::Uint(index),
            Token::Uint(U256::from(u64::from_le_bytes(
                to_bytes(score).expect("read value has the wrong size"),
            ))),
            Token::FixedBytes(log_hash.to_vec()),
            Token::FixedBytes(final_hash.0.to_vec()),
            Token::Array(log_siblings),
            Token::Array(score_siblings),
        ],
        strategy: transaction::Strategy::Simplest,
    };

    return Ok(Reaction::Transaction(request));
}
