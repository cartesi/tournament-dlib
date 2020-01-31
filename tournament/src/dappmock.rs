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

use super::dispatcher::{Archive, DApp, Reaction};
use super::dispatcher::{String32Field, U256Field};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::U256;
use super::revealmock::{RevealMock, RevealMockCtx, RevealMockCtxParsed};
use super::transaction;
use super::transaction::TransactionRequest;

pub struct DAppMock();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
struct DAppMockCtxParsed(
    U256Field,     // revealIndex
    String32Field, // currentState
);

#[derive(Serialize, Debug)]
struct DAppMockCtx {
    reveal_index: U256,
    current_state: String,
}

impl From<DAppMockCtxParsed> for DAppMockCtx {
    fn from(parsed: DAppMockCtxParsed) -> DAppMockCtx {
        DAppMockCtx {
            reveal_index: parsed.0.value,
            current_state: parsed.1.value,
        }
    }
}

impl DApp<()> for DAppMock {
    /// React to the DApp contract, submitting solutions, confirming
    /// or challenging them when appropriate
    fn react(
        instance: &state::Instance,
        archive: &Archive,
        post_payload: &Option<String>,
        _: &(),
    ) -> Result<Reaction> {
        // get context (state) of the compute instance
        let parsed: DAppMockCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse compute instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: DAppMockCtx = parsed.into();
        trace!("Context for mockDApp (index {}) {:?}", instance.index, ctx);

        // these states should not occur as they indicate an innactive instance,
        // but it is possible that the blockchain state changed between queries
        match ctx.current_state.as_ref() {
            "DAppFinished" => {
                return Ok(Reaction::Idle);
            }

            "Idle" => {
                println!("STATE is IDLE");
                let request = TransactionRequest {
                    concern: instance.concern.clone(),
                    value: U256::from(0),
                    function: "claimDAppRunning".into(),
                    data: vec![Token::Uint(instance.index)],
                    gas: None,
                    strategy: transaction::Strategy::Simplest,
                };

                return Ok(Reaction::Transaction(request));
            }

            "DAppRunning" => {
                // we inspect the reveal contract
                let revealmock_instance = instance.sub_instances.get(0).ok_or(Error::from(
                    ErrorKind::InvalidContractState(format!(
                        "There is no reveal instance {}",
                        ctx.current_state
                    )),
                ))?;

                let revealmock_parsed: RevealMockCtxParsed =
                    serde_json::from_str(&revealmock_instance.json_data).chain_err(|| {
                        format!(
                            "Could not parse revealmock instance json_data: {}",
                            &revealmock_instance.json_data
                        )
                    })?;
                let revealmock_ctx: RevealMockCtx = revealmock_parsed.into();

                match revealmock_ctx.current_state.as_ref() {
                    "TournamentOver" => {
                        // claim Finished in dappmock test contract
                        let request = TransactionRequest {
                            concern: instance.concern.clone(),
                            value: U256::from(0),
                            function: "claimFinished".into(),
                            data: vec![Token::Uint(instance.index)],
                            gas: None,
                            strategy: transaction::Strategy::Simplest,
                        };
                        return Ok(Reaction::Transaction(request));
                    }
                    _ => {
                        // revealMock is still active,
                        // pass control to the appropriate dapp
                        return RevealMock::react(revealmock_instance, archive, post_payload, &());
                    }
                }
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
        let parsed: DAppMockCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse match instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: DAppMockCtx = parsed.into();
        let json_data = serde_json::to_string(&ctx).unwrap();

        // get context (state) of the sub instances

        let mut pretty_sub_instances: Vec<Box<state::Instance>> = vec![];

        for sub in &instance.sub_instances {
            pretty_sub_instances.push(Box::new(
                RevealMock::get_pretty_instance(sub, archive, &()).unwrap(),
            ))
        }

        let pretty_instance = state::Instance {
            name: "DAppMock".to_string(),
            concern: instance.concern.clone(),
            index: instance.index,
            json_data: json_data,
            sub_instances: pretty_sub_instances,
        };

        return Ok(pretty_instance);
    }
}
