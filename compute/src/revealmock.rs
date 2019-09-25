use super::configuration::Concern;
use super::dispatcher::{AddressField, Bytes32Field, String32Field, U256Field};
use super::dispatcher::{Archive, DApp, Reaction};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use super::transaction;
use super::transaction::TransactionRequest;
use super::{Role};

use matchmanager::{MatchManagerCtx, MatchManagerCtxParsed}

use std::time::{SystemTime, UNIX_EPOCH};

pub struct RevealMock();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
pub struct RevealMockCtxParsed(
    U256Field,     // commitDuration;
    U256Field,     // revealDuration;
    U256Field,     // creationTime;
    U256Field,     // matchManagerIndex;
    U256Field,     // matchManagerEpochDuration;
    U256Field,     // matchManagerMatchDuration;
    U256Field,     // finalTime;
    Bytes32Field,  // initialHash;
    AddressField,  // machineAddress;
    String32Field, // currentState
);

#[derive(Debug)] pub struct RevealMockCtx {
    commit_duration: U256,
    reveal_duration: U256,
    creation_time: U256,
    match_manager_index: U256,
    match_manager_epoch_duration: U256,
    match_manager_match_duration: U256,
    final_time: U256,
    initial_hash: H256,
    machine_address: Address,
    current_state: String,
    }

impl From<RevealMockCtxParsed> for MockRevealCtx {
    fn from(parsed: RevealMockCtxParsed) -> MatchManagerCtx {
        RevealMockCtx {
            commit_duration: parsed.0.value,
            reveal_duration: parsed.1.value,
            creation_time: parsed.2.value,
            match_manager_index: parsed.3.value,
            match_manager_epoch_duration: parsed.4.value,
            match_manager_match_duration: parsed.5.value,
            final_time: parsed.6.value,
            initial_hash: parsed.7.value,
            machine_address: parsed.8.value,
            current_state: parsed.9.value,
        }
    }
}

// TO-DO: use state to check if player is already registered
// state check for time of last epoch
// state check if youre unmatched player
// state check if number of matches played on last epoch was 0
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
                    "Could not parse match instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: RevelMockCtx = parsed.into();
        trace!("Context for match (index {}) {:?}", instance.index, ctx);

        match ctx.current_state.as_ref() {
            // these states should not occur as they indicate an innactive instance,
            // but it is possible that the blockchain state changed between queries
            "CommitPhase" 
            | "RevealPhase" => {
                return Ok(Reaction::Idle);
            }

            "MatchManagerPhase" => {
                let match_manager_instance = instance.sub_instances.get(0).ok_or(
                    Error::from(ErrorKind::InvalidContractState(format!(
                        "There is no match instance {}",
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

                // also has to check if player is not unmatched address
                if (match_manager_ctx.last_match_epoch == 0) {
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
            }

            "TournamentOver" => {
                return Ok(Reaction::Idle);
            }
            _ => {
                return Ok(Reaction::Idle);
            }
        }
    }
}

