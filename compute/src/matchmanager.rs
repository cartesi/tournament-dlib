use super::configuration::Concern;
use super::dispatcher::{AddressField, Bytes32Field, String32Field, U256Field, AddressArray3, U256Array9, BoolField};
use super::dispatcher::{Archive, DApp, Reaction};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use super::transaction;
use super::transaction::TransactionRequest;
use super::{Match, Role};
use r#match::{MatchCtx, MatchCtxParsed};

use std::time::{SystemTime, UNIX_EPOCH};

pub struct MatchManager();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
pub struct MatchManagerCtxParsed(
    U256Array9,     // epochDuration
                    // roundDuration
                    // currentEpoch
                    // finalTime
                    // lastEpochStartTime
                    // numberOfMatchesOnEpoch
                    // lastMatchIndex
                    // revealInstance
                    // lastMatchEpoch

    AddressArray3,  // unmatchedplayer
                    // machine
                    // revealaddress

    Bytes32Field,   // initialhash
    BoolField,      // registered
    String32Field,  // currentstate
);

#[derive(Debug)]
pub struct MatchManagerCtx {
   pub epoch_duration: U256,
   pub round_duration: U256,
   pub current_epoch: U256,
   pub final_time: U256,
   pub last_epoch_start_time: U256,
   pub number_of_matches_on_last_epoch: U256,
   pub unmatched_player: Address,
   pub last_match_index: U256,
   pub initial_hash: H256,
   pub machine: Address,
   pub reveal_address: Address,
   pub reveal_instance: U256,
   pub last_match_epoch: U256,
   pub registered: bool,
   pub current_state: String,
}


impl From<MatchManagerCtxParsed> for MatchManagerCtx {
    fn from(parsed: MatchManagerCtxParsed) -> MatchManagerCtx {
        MatchManagerCtx {
            epoch_duration: parsed.0.value[0],
            round_duration: parsed.0.value[1],
            current_epoch: parsed.0.value[2],
            final_time: parsed.0.value[3],
            last_epoch_start_time: parsed.0.value[4],
            number_of_matches_on_last_epoch: parsed.0.value[5],
            last_match_index: parsed.0.value[6],
            reveal_instance: parsed.0.value[7],
            last_match_epoch: parsed.0.value[8],

            unmatched_player: parsed.1.value[0],
            machine: parsed.1.value[1],
            reveal_address: parsed.1.value[2],

            initial_hash: parsed.2.value,
            registered: parsed.3.value,
            current_state: parsed.4.value,
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
        trace!("Context for matchmanager (index {}) {:?}", instance.index, ctx);

        match ctx.current_state.as_ref() {
            // these states should not occur as they indicate an innactive instance,
            // but it is possible that the blockchain state changed between queries
            "MatchesOver"
            | "WaitingSignUps" => {
                return Ok(Reaction::Idle);
            }

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

                // if player hasnt registered yet and epoch is zero, register:
                if ctx.current_epoch.as_u64() == 0 && !ctx.registered {
                    let request = TransactionRequest {
                        concern: instance.concern.clone(),
                        value: U256::from(0),
                        function: "playNextEpoch".into(),
                        data: vec![Token::Uint(instance.index)],
                        strategy: transaction::Strategy::Simplest,
                    };
                    return Ok(Reaction::Transaction(request));
                }

                // if player already played epoch, returns idle
                //let played_current_epoch = ctx.last_match_epoch == ctx.current_epoch;
                //if (!epoch_over && played_current_epoch) || user_is_unmatched
                //    || (ctx.registered && ctx.current_epoch.as_u64() == 0)
                //{
                //    return Ok(Reaction::Idle);
                //}

                // if player havent played epoch and its not the first one,
                // we have to inspect the matches to see if he won the previous one.
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
                                "Could not parse match instance json_data: {}",
                                &match_instance.json_data
                            )
                        })?;
                let match_ctx: MatchCtx = match_parsed.into();

                println!("CLAIMER ADDR IS {}", match_ctx.claimer);
                println!("CHALLENGER ADDR IS {}", match_ctx.challenger);

                println!("MatchInstance {:?}", match_instance);
                println!("Match_CTX {:?}", match_ctx);

                let role = match instance.concern.user_address {
                    cl if (cl == match_ctx.claimer) => Role::Claimer,
                    ch if (ch == match_ctx.challenger) => Role::Challenger,
                    _ => {
                        return Err(Error::from(ErrorKind::InvalidContractState(
                            String::from("User is neither claimer nor challenger"),
                        )));
                    }
                };

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

                        // you lost the previous game, so nothing else to do
                        "ChallengerWon" => {
                            return Ok(Reaction::Idle);
                        }
                        _ => {
                            // match is still running,
                            // pass control to the match instance
                            return Match::react(
                                match_instance,
                                archive,
                                &(),
                            );
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

                        // you lost the previous game, so nothing else to do 
                        "ClaimerWon" => {
                            return Ok(Reaction::Idle);
                        }

                        _ => {
                            // match is still running,
                            // pass control to the match instance
                            return Match::react(
                                match_instance,
                                archive,
                                &(),
                            );
                        }
                    }

                }
            }

            _ => {
                return Ok(Reaction::Idle);
            }
        }
    }
}

