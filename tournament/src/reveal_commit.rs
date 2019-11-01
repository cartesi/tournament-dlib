use super::configuration::Concern;
use super::dispatcher::{AddressField, Bytes32Field, String32Field, U256Field, U256Array, U256Array6, BoolField};
use super::dispatcher::{Archive, DApp, Reaction};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use super::transaction;
use super::transaction::TransactionRequest;
use super::{
    LOGGER_SERVICE_NAME, LOGGER_METHOD_SUBMIT,
    LOGGER_METHOD_DOWNLOAD, FilePath, Hash};

use std::time::{SystemTime, UNIX_EPOCH};

pub struct RevealCommit();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
pub struct RevealCommitCtxParsed(
    pub U256Array6,     // instantiatedAt
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

#[derive(Deserialize, Debug)]
struct Payload {
    action: String,
    params: Params
}

#[derive(Deserialize, Debug)]
struct Params {
    hash: String,
    path: String
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

impl DApp<()> for RevealCommit {
    /// React to the Reveal contract
    fn react(
        instance: &state::Instance,
        archive: &Archive,
        post_payload: &Option<String>,
        _: &(),
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
        trace!("Context for reveal_commit (index {}) {:?}", instance.index, ctx);

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
                let phase_is_over = current_time > ctx.instantiated_at.as_u64() + ctx.commit_duration.as_u64();

                if phase_is_over {
                    // if commit phase is over, player reveal his log and forces the phase change
                    // TO-DO: complete transaction parameters
                    let request = TransactionRequest {
                        concern: instance.concern.clone(),
                        value: U256::from(0),
                        function: "reveal".into(),
                        data: vec![
                            Token::Uint(instance.index),
                            //Token::Uint(score),
                            //Token::FixedBytes(finalHash),
                            //Token::FixedBytes(logDriveHash),
                            //Token::FixedBytes(scoreDriveHash),
                            //Token::Array(logDriveSiblings),
                            //Token::Array(scoreDriveSiblings)
                        ],
                        strategy: transaction::Strategy::Simplest,
                    };

                    return Ok(Reaction::Transaction(request));

                }
                // if current highscore > previous highscore, commit
                // else:
                return Ok(Reaction::Idle);
            }


            "RevealPhase" => {
                let phase_is_over = current_time > ctx.instantiated_at.as_u64() + ctx.commit_duration.as_u64() + ctx.reveal_duration.as_u64();

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
                
                match post_payload {
                    Some(s) => {
                        let payload: Payload = serde_json::from_str(&s).chain_err(|| {
                            format!("Could not parse post_payload: {}", &s)
                        })?;
                        match payload.action.as_ref() {
                            "logger.upload" => {
                                // submit file to logger
                                let path = payload.params.path.clone();
                                trace!("Submitting file: {}...", path);
                                let request = FilePath {
                                    path: path.clone()
                                };

                                let processed_response: Hash = archive.get_response(
                                    LOGGER_SERVICE_NAME.to_string(),
                                    path.clone(),
                                    LOGGER_METHOD_SUBMIT.to_string(),
                                    request.into())?
                                    .map_err(move |_e| {
                                        Error::from(ErrorKind::ArchiveInvalidError(
                                            LOGGER_SERVICE_NAME.to_string(),
                                            path,
                                            LOGGER_METHOD_SUBMIT.to_string()))
                                    })?
                                    .into();
                                trace!("Submitted! Result: {:?}...", processed_response.hash);
                            },
                            _ => {
                                return Ok(Reaction::Idle);
                            }
                        }
                    },
                    None => {
                        return Ok(Reaction::Idle);
                    }
                }

                // else complete reveal
                // TO-DO: complete transaction parameters
                let request = TransactionRequest {
                    concern: instance.concern.clone(),
                    value: U256::from(0),
                    function: "reveal".into(),
                    data: vec![
                        Token::Uint(instance.index),
                        //Token::Uint(score),
                        //Token::FixedBytes(finalHash),
                        //Token::FixedBytes(logDriveHash),
                        //Token::FixedBytes(scoreDriveHash),
                        //Token::Array(logDriveSiblings),
                        //Token::Array(scoreDriveSiblings)
                    ],
                    strategy: transaction::Strategy::Simplest,
                };

                return Ok(Reaction::Transaction(request));


            }

            _ => {
                return Ok(Reaction::Idle);
            }
        }
    }

    fn get_pretty_instance(
        instance: &state::Instance,
        archive: &Archive,
        _: &(),
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

        let pretty_sub_instances : Vec<Box<state::Instance>> = vec![];

        let pretty_instance = state::Instance {
            name: "RevealCommit".to_string(),
            concern: instance.concern.clone(),
            index: instance.index,
            json_data: json_data,
            sub_instances: pretty_sub_instances,
        };

        return Ok(pretty_instance)
    }
}

