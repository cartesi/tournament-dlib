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
use r#match::{MatchCtx, MatchCtxParsed};

use std::time::{SystemTime, UNIX_EPOCH};

pub struct MatchManager();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
struct MatchManagerCtxParsed(
    U256Field,     // epochDuration
    U256Field,     // roundDuration
    U256Field,     // currentEpoch
    U256Field,     // finalTime
    U256Field,     // lastEpochStartTime
    U256Field,     // numberOfMatchesOnEpoch
    AddressField,  // unmatchedPlayer
    U256Field,     // lastMatchIndex
    Bytes32Field,  // initialHash
    AddressField,  // machine
    AddressField,  // RevealAddress
    U256Field,     // revealInstance
    U256Field,     // lastMatchEpoch
    String32Field, // currentState
);

#[derive(Debug)]
struct MatchManagerCtx {
    epoch_duration: U256,
    round_duration: U256,
    current_epoch: U256,
    final_time: U256,
    last_epoch_start_time: U256,
    number_of_matches_on_last_epoch: U256,
    unmatched_player: Address,
    last_match_index: U256,
    initial_hash: H256,
    machine: Address,
    reveal_address: Address,
    reveal_instance: U256,
    last_match_epoch: U256,
    current_state: String,
}

impl From<MatchManagerCtxParsed> for MatchManagerCtx {
    fn from(parsed: MatchManagerCtxParsed) -> MatchManagerCtx {
        MatchManagerCtx {
            epoch_duration: parsed.0.value,
            round_duration: parsed.1.value,
            current_epoch: parsed.2.value,
            final_time: parsed.3.value,
            last_epoch_start_time: parsed.4.value,
            number_of_matches_on_last_epoch: parsed.5.value,
            unmatched_player: parsed.6.value,
            last_match_index: parsed.7.value,
            initial_hash: parsed.8.value,
            machine: parsed.9.value,
            reveal_address: parsed.10.value,
            reveal_instance: parsed.11.value,
            last_match_epoch: parsed.12.value,
            current_state: parsed.13.value,

        }
    }
}

// TO-DO: use state to check if player is already registered
// state check for time of last epoch
// state check if youre unmatched player
// state check if number of matches played on last epoch was 0
impl DApp<()> for MatchManager {
    /// React to the Match contract, submitting solutions, confirming
    /// or challenging them when appropriate
    fn react(
        instance: &state::Instance,
        archive: &Archive,
        _: &(),
    ) -> Result<Reaction> {
        // get context (state) of the match instance
        let parsed: MatchManagerCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse match instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: MatchManagerCtx = parsed.into();
        trace!("Context for match (index {}) {:?}", instance.index, ctx);

        // these states should not occur as they indicate an innactive instance,
        // but it is possible that the blockchain state changed between queries
        match ctx.current_state.as_ref() {
            // TO-DO: First registration must come from Reveal contract?
            "MatchesOver" 
            | "WaitingSignUps" => {
                return Ok(Reaction::Idle);
            }
            _ => {}
        };


        match ctx.current_state.as_ref() {
            "WaitingMatches" => {
                // we inspect the match contract
                let current_time = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .chain_err(|| "System time before UNIX_EPOCH")?
                    .as_secs();

                let epoch_over = current_time > ctx.last_epoch_start_time.as_u64() + ((1 + ctx.current_epoch.as_u64()) * ctx.epoch_duration.as_u64());
                let zero_matches_last_epoch = ctx.number_of_matches_on_last_epoch.as_u64() == 0;
                let user_is_unmatched = ctx.unmatched_player == instance.concern.user_address;

                // if player won, claims victory
                if epoch_over && zero_matches_last_epoch && user_is_unmatched {
                    let request = TransactionRequest {
                    concern: instance.concern.clone(),
                    value: U256::from(0),
                    function: "claimWin".into(),
                    data: vec![Token::Uint(instance.index)],
                    strategy: transaction::Strategy::Simplest,
                    };

                    return Ok(Reaction::Transaction(request));
                }

                // if player already played epoch, returns idle
                let played_current_epoch = ctx.last_match_epoch == ctx.current_epoch;
                if (!epoch_over && played_current_epoch) || user_is_unmatched {
                    return Ok(Reaction::Idle);
                }

                let match_instance = instance.sub_instances.get(0).ok_or(
                    Error::from(ErrorKind::InvalidContractState(format!(
                        "There is no match instance {}",
                        ctx.current_state
                    ))),
                )?;


                let match_parsed: MatchCtxParsed =
                    serde_json::from_str(&match_instance.json_data)
                        .chain_err(|| {
                            format!(
                                "Could not parse vg instance json_data: {}",
                                &match_instance.json_data
                            )
                        })?;
                let match_ctx: MatchCtx = match_parsed.into();

                let role = match instance.concern.user_address {
                    cl if (cl == match_ctx.claimer) => Role::Claimer,
                    ch if (ch == match_ctx.challenger) => Role::Challenger,
                    _ => {
                        return Err(Error::from(ErrorKind::InvalidContractState(
                            String::from("User is neither claimer nor challenger"),
                        )));
                    }
                };
                trace!("Role played (index {}) is: {:?}", match_instance, role);
                match role {
                    Role::Claimer => match match_ctx.current_state.as_ref() {
                        "ClaimerWon" => {
                            let request = TransactionRequest {
                            concern: instance.concern.clone(),
                            value: U256::from(0),
                            function: "playNextEpoch".into(),
                            data: vec![Token::Uint(instance.index)],
                            strategy: transaction::Strategy::Simplest,
                        };
                            return Ok(Reaction::Transaction(request));

                        }
                    }
                    Role::Challenger => match match_ctx.current_state.as_ref() {
                        "ChallengerWon" => {
                            let request = TransactionRequest {
                            concern: instance.concern.clone(),
                            value: U256::from(0),
                            function: "playNextEpoch".into(),
                            data: vec![Token::Uint(instance.index)],
                            strategy: transaction::Strategy::Simplest,
                        };
                        return Ok(Reaction::Transaction(request));

                        }
                    }
                }
            }
        }
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
