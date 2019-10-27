use super::configuration::Concern;
use super::dispatcher::{AddressField, Bytes32Field, String32Field, U256Field, U256Array, U256Array5, BoolField};
use super::dispatcher::{Archive, DApp, Reaction};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use super::transaction;
use super::transaction::TransactionRequest;


pub struct RevealCommit();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
pub struct RevealCommitCtxParsed(
    pub U256Field,     // instantiatedAt
    pub U256Field,     // commitDuration
    pub U256Field,     // revealDuration
    pub U256Field,     // finalTime

    pub Bytes32Field   // pristineHash;

    pub U256Field,     // scoreDrivePosition
    pub U256Field,     // logDrivePosition
    pub U256Field,     // scoreDriveLogSize
    pub U256Field,     // logDriveLogSize
    pub U256Field,     // logDriveLogSize

    pub BoolField,     // hasRevealed

    pub String32Field, // currentState
);

#[derive(Serialize, Debug)]
pub struct RevealCommitCtx {
    pub instantiated_at: U256,
    pub commit_duration: U256,
    pub reveal_duration: U256,
    pub final_time: U256,
    pub pristine_hash: H256,

    pub score_drive_position: U256,
    pub log_drive_position: U256,
    pub score_drive_log_size: U256,
    pub log_drive_log_size: U256,

    pub has_revealed: bool,

    pub current_state: String,
}

impl From<RevealCommitCtxParsed> for RevealCommitCtx {
    fn from(parsed: RevealCommitCtxParsed) -> RevealCommitCtx {
        RevealCommitCtx {
            instantiated_at: parsed.0.value
            commit_duration: parsed.1.value
            reveal_duration: parsed.2.value
            final_time: parsed.3.value
            pristine_hash: parsed.4.value
            score_drive_position: parsed.5.value
            log_drive_position: parsed.6.value
            score_drive_log_size: parsed.7.value
            log_drive_log_size: parsed.8.value
            current_state: parsed.9.value
        }
    }
}

impl DApp<()> for RevealCommit {
    /// React to the Reveal contract
    fn react(
        instance: &state::Instance,
        archive: &Archive,
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
                let phase_is_over = current_time > ctx.instantiated_at + ctx.commit_duration;

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
                let phase_is_over = current_time > ctx.instantiated_at + ctx.commit_duration + ctx.reveal_duration;

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
                Ok(Reaction::Idle);
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

