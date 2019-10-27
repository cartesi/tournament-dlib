use super::configuration::Concern;
use super::dispatcher::{AddressField, Bytes32Field, String32Field, U256Field, U256Array, U256Array5};
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

        match ctx.current_state.as_ref() {
            "CommitRevealDone" => {
                return Ok(Reaction::Idle);
            }

            "CommitPhase" => {}

            "RevealPhase" => {}

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

