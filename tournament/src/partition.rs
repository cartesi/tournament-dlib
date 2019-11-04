// Arbitration DLib is the combination of the on-chain protocol and off-chain
// protocol that work together to resolve any disputes that might occur during the
// execution of a Cartesi DApp.

// Copyright (C) 2019 Cartesi Pte. Ltd.

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


use super::{build_machine_id, build_session_run_key};
use super::dispatcher::{
    AddressField, BoolArray, Bytes32Array, String32Field, U256Array, U256Array5,
};
use super::dispatcher::{Archive, DApp, Reaction};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use super::transaction::TransactionRequest;
use super::{Role, SessionRunRequest, SessionRunResult, EMULATOR_SERVICE_NAME, EMULATOR_METHOD_RUN};
use compute::win_by_deadline_or_idle;

pub struct Partition();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
pub struct PartitionCtxParsed(
    pub AddressField,  // challenger
    pub AddressField,  // claimer
    pub U256Array,     // queryArray
    pub BoolArray,     // submittedArray
    pub Bytes32Array,  // hashArray
    pub String32Field, // currentState
    pub U256Array5,    // uint values: finalTime
                       // querySize
                       // timeOfLastMove
                       // roundDuration
                       // divergenceTime
);

#[derive(Serialize, Debug)]
pub struct PartitionCtx {
    pub challenger: Address,
    pub claimer: Address,
    pub query_array: Vec<U256>,
    pub submitted_array: Vec<bool>,
    pub hash_array: Vec<H256>,
    pub current_state: String,
    pub final_time: U256,
    pub query_size: U256,
    pub time_of_last_move: U256,
    pub round_duration: U256,
    pub divergence_time: U256,
}

impl From<PartitionCtxParsed> for PartitionCtx {
    fn from(parsed: PartitionCtxParsed) -> PartitionCtx {
        PartitionCtx {
            challenger: parsed.0.value,
            claimer: parsed.1.value,
            query_array: parsed.2.value,
            submitted_array: parsed.3.value,
            hash_array: parsed.4.value,
            current_state: parsed.5.value,
            final_time: parsed.6.value[0],
            query_size: parsed.6.value[1],
            time_of_last_move: parsed.6.value[2],
            round_duration: parsed.6.value[3],
            divergence_time: parsed.6.value[4],
        }
    }
}

impl DApp<()> for Partition {
    fn react(
        instance: &state::Instance,
        archive: &Archive,
        post_action: &Option<String>,
        _: &(),
    ) -> Result<Reaction> {
        let parsed: PartitionCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse partition instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: PartitionCtx = parsed.into();
        trace!("Context for parition {:?}", ctx);

        // should not happen as it indicates an innactive instance,
        // but it is possible that the blockchain state changed between queries
        match ctx.current_state.as_ref() {
            "ChallengerWon" | "ClaimerWon" | "DivergenceFound" => {
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
                "WaitingQuery" => {
                    return win_by_deadline_or_idle(
                        &instance.concern,
                        instance.index,
                        ctx.time_of_last_move.as_u64(),
                        ctx.round_duration.as_u64(),
                    );
                }
                "WaitingHashes" => {
                    // machine id
                    let id = build_machine_id(
                        instance.index,
                        &instance.concern.contract_address,
                    );
                    
                    trace!("Calculating queried hashes of machine {}", id);
                    let sample_points: Vec<u64> = ctx
                        .query_array
                        .clone()
                        .into_iter()
                        .map(|u| u.as_u64())
                        .collect();
                    let request = SessionRunRequest {
                        session_id: id.clone(),
                        times: sample_points.clone(),
                    };
                    let archive_key = build_session_run_key(
                        id.clone(),
                        sample_points.clone());

                    // have we sampled the times?
                    let processed_response: SessionRunResult = archive.get_response(
                        EMULATOR_SERVICE_NAME.to_string(),
                        archive_key.clone(),
                        EMULATOR_METHOD_RUN.to_string(),
                        request.into())?
                        .map_err(move |_e| {
                            Error::from(ErrorKind::ArchiveInvalidError(
                                EMULATOR_SERVICE_NAME.to_string(),
                                id,
                                EMULATOR_METHOD_RUN.to_string()))
                        })?
                        .into();

                    let mut hashes = Vec::new();

                    for i in 0..ctx.query_size.as_usize() {
                        // get the i'th time in query array
                        let _time = &ctx.query_array.get(i).ok_or(
                            Error::from(ErrorKind::InvalidContractState(
                                String::from(
                                    "could not find element in query array",
                                ),
                            )),
                        )?;
                        let hash = processed_response.hashes.get(i).unwrap();
                        hashes.push(hash);
                    }
                    // submit the required hashes
                    let request = TransactionRequest {
                        concern: instance.concern.clone(),
                        value: U256::from(0),
                        function: "replyQuery".into(),
                        // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                        // improve these types by letting the
                        // dapp submit ethereum_types and convert
                        // them inside the transaction manager
                        // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                        data: vec![
                            Token::Uint(instance.index),
                            Token::Array(
                                ctx.query_array
                                    .clone()
                                    .iter_mut()
                                    .map(|q: &mut U256| -> _ {
                                        Token::Uint(q.clone())
                                    })
                                    .collect(),
                            ),
                            Token::Array(
                                hashes
                                    .into_iter()
                                    .map(|h| -> _ {
                                        Token::FixedBytes(
                                            h.clone().to_vec(),
                                        )
                                    })
                                    .collect(),
                            ),
                        ],
                        strategy: transaction::Strategy::Simplest,
                    };
                    return Ok(Reaction::Transaction(request));
                }
                _ => {
                    return Err(Error::from(ErrorKind::InvalidContractState(
                        format!("Unknown current state {}", ctx.current_state),
                    )));
                }
            },
            Role::Challenger => match ctx.current_state.as_ref() {
                "WaitingQuery" => {
                    // machine id
                    let id = build_machine_id(
                        instance.index,
                        &instance.concern.contract_address,
                    );
                    
                    trace!("Calculating posted hashes of machine {}", id);
                    let sample_points: Vec<u64> = ctx
                        .query_array
                        .clone()
                        .into_iter()
                        .map(|u| u.as_u64())
                        .collect();
                    let request = SessionRunRequest {
                        session_id: id.clone(),
                        times: sample_points.clone(),
                    };
                    let archive_key = build_session_run_key(
                        id.clone(),
                        sample_points.clone());

                    // have we sampled the times?
                    let processed_response: SessionRunResult = archive.get_response(
                        EMULATOR_SERVICE_NAME.to_string(),
                        archive_key.clone(),
                        EMULATOR_METHOD_RUN.to_string(),
                        request.into())?
                        .map_err(move |_e| {
                            Error::from(ErrorKind::ArchiveInvalidError(
                                EMULATOR_SERVICE_NAME.to_string(),
                                id,
                                EMULATOR_METHOD_RUN.to_string()))
                        })?
                        .into();

                    for i in 0..(ctx.query_size.as_usize() - 1) {
                        // get the i'th time in query array
                        let time =
                            ctx.query_array.get(i).ok_or(Error::from(
                                ErrorKind::InvalidContractState(format!(
                                "could not find element {} in query array",
                                i
                            )),
                            ))?;
                        // get (i + 1)'th time in query array
                        let next_time = ctx.query_array.get(i + 1).ok_or(
                            Error::from(ErrorKind::InvalidContractState(
                                format!(
                                "could not find element {} in query array",
                                i + 1
                            ),
                            )),
                        )?;
                        // get the (i + 1)'th hash in hash array
                        let claimed_hash = &ctx
                            .hash_array
                            .get(i + 1)
                            .ok_or(Error::from(
                                ErrorKind::InvalidContractState(format!(
                                "could not find element {} in hash array",
                                i
                            )),
                            ))?;
                        // have we sampled that specific time?
                        let hash = processed_response.hashes.get(i + 1).unwrap();

                        if hash != *claimed_hash {
                            // do we need another partition?
                            if next_time.as_u64() - time.as_u64() > 1 {
                                // submit the relevant query
                                let request = TransactionRequest {
                                    concern: instance.concern.clone(),
                                    value: U256::from(0),
                                    function: "makeQuery".into(),
                                    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                                    // improve these types by letting the
                                    // dapp submit ethereum_types and convert
                                    // them inside the transaction manager
                                    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                                    data: vec![
                                        Token::Uint(instance.index),
                                        Token::Uint(U256::from(i)),
                                        Token::Uint(*time),
                                        Token::Uint(*next_time),
                                    ],
                                    strategy:
                                        transaction::Strategy::Simplest,
                                };
                                return Ok(Reaction::Transaction(request));
                            } else {
                                // submit divergence time
                                let request = TransactionRequest {
                                    concern: instance.concern.clone(),
                                    value: U256::from(0),
                                    function: "presentDivergence".into(),
                                    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                                    // improve these types by letting the
                                    // dapp submit ethereum_types and convert
                                    // them inside the transaction manager
                                    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                                    data: vec![
                                        Token::Uint(instance.index),
                                        Token::Uint(*time),
                                    ],
                                    strategy:
                                        transaction::Strategy::Simplest,
                                };
                                return Ok(Reaction::Transaction(request));
                            }
                        }
                    }
                    // no disagreement found. important bug!!!!
                    error!(
                        "bug found: no disagreement in dispute {:?}!!!",
                        instance
                    );
                    return Err(Error::from(format!("no disagreement in dispute")));
                }
                "WaitingHashes" => {
                    return win_by_deadline_or_idle(
                        &instance.concern,
                        instance.index,
                        ctx.time_of_last_move.as_u64(),
                        ctx.round_duration.as_u64(),
                    );
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
        _: &(),
    ) -> Result<state::Instance> {
        
        // get context (state) of the match instance
        let parsed: PartitionCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse match instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: PartitionCtx = parsed.into();
        let json_data = serde_json::to_string(&ctx).unwrap();

        // get context (state) of the sub instances

        let pretty_sub_instances : Vec<Box<state::Instance>> = vec![];

        let pretty_instance = state::Instance {
            name: "Partition".to_string(),
            concern: instance.concern.clone(),
            index: instance.index,
            json_data: json_data,
            sub_instances: pretty_sub_instances,
        };

        return Ok(pretty_instance)
    }
}
