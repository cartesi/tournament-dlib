use super::configuration::Concern;
use super::dispatcher::{AddressField, Bytes32Field, String32Field, U256Field, U256Array, U256Array5};
use super::dispatcher::{Archive, DApp, Reaction};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use matchmanager::MatchManager;
use super::transaction;
use super::transaction::TransactionRequest;

use matchmanager::{MatchManagerCtx, MatchManagerCtxParsed};

pub struct RevealMock();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
pub struct RevealMockCtxParsed(
    pub U256Array5,     // commitDuration;
                       // revealDuration;
                       // matchManagerEpochDuration;
                       // matchManagerMatchDuration;
                       // finalTime;
    pub Bytes32Field,  // initialHash;
    pub AddressField,  // machineAddress;
    pub String32Field, // currentState
);

#[derive(Debug)]
pub struct RevealMockCtx {
    pub commit_duration: U256,
    pub reveal_duration: U256,
    pub match_manager_epoch_duration: U256,
    pub match_manager_match_duration: U256,
    pub final_time: U256,
    pub initial_hash: H256,
    pub machine_address: Address,
    pub current_state: String,
}

impl From<RevealMockCtxParsed> for RevealMockCtx {
    fn from(parsed: RevealMockCtxParsed) -> RevealMockCtx {
        RevealMockCtx {
            commit_duration: parsed.0.value[0],
            reveal_duration: parsed.0.value[1],
            match_manager_epoch_duration: parsed.0.value[2],
            match_manager_match_duration: parsed.0.value[3],
            final_time: parsed.0.value[4],
            initial_hash: parsed.1.value,
            machine_address: parsed.2.value,
            current_state: parsed.3.value,
        }
    }
}

impl DApp<()> for RevealMock {
    /// React to the Reveal contract, submitting solutions, confirming
    /// or challenging them when appropriate
    fn react(
        instance: &state::Instance,
        archive: &Archive,
        _: &(),
    ) -> Result<Reaction> {
        // get context (state) of the match instance
        let parsed: RevealMockCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse reveal instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: RevealMockCtx = parsed.into();
        trace!("Context for revealmock (index {}) {:?}", instance.index, ctx);

        match ctx.current_state.as_ref() {
            // TO-DO: RevealMock should never be in these states. Add warning.
            "CommitPhase"
            | "RevealPhase" => {
                return Ok(Reaction::Idle);
            }

            "MatchManagerPhase" => {
                let match_manager_instance = instance.sub_instances.get(0).ok_or(
                    Error::from(ErrorKind::InvalidContractState(format!(
                        "There is no match manager instance {}",
                        ctx.current_state
                    ))),
                )?;

                let match_manager_parsed: MatchManagerCtxParsed =
                    serde_json::from_str(&match_manager_instance.json_data)
                        .chain_err(|| {
                            format!(
                                "Could not parse match manager instance json_data: {}",
                                &match_manager_instance.json_data
                            )
                        })?;
                let match_manager_ctx: MatchManagerCtx = match_manager_parsed.into();
                let user_is_unmatched = match_manager_ctx.unmatched_player == instance.concern.user_address;

                // Reveal is responsible for registering player to first epoch.
                // this should probably change soon
                if match_manager_ctx.last_match_epoch.as_u64() == 0 && !user_is_unmatched {
                    // register to first epoch
                    let request = TransactionRequest {
                        concern: instance.concern.clone(),
                        value: U256::from(0),
                        function: "registerToFirstEpoch".into(),
                        data: vec![Token::Uint(instance.index)],
                        strategy: transaction::Strategy::Simplest,
                    };
                    return Ok(Reaction::Transaction(request));
                }

               // if last_match_epoch > zero, control goes to matchmanager
                return MatchManager::react(
                    match_manager_instance,
                    archive,
                    &(),
                );
            }

            "TournamentOver" => {
                // claim Finished in dappmock test contract
                let request = TransactionRequest {
                    concern: instance.concern.clone(),
                    value: U256::from(0),
                    function: "claimFinished".into(),
                    data: vec![Token::Uint(instance.index)],
                    strategy: transaction::Strategy::Simplest,
                };
                return Ok(Reaction::Transaction(request));
            }
            _ => {
                return Ok(Reaction::Idle);
            }
        }
    }
}

