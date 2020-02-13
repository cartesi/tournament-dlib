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

use super::dispatcher::{AddressField, Bytes32Field, String32Field, U256Array5};
use super::dispatcher::{Archive, DApp, Reaction};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use super::transaction;
use super::transaction::TransactionRequest;
use matchmanager::MatchManager;

pub struct RevealMock();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
pub struct RevealMockCtxParsed(
    pub U256Array5, // commitDuration;
    // revealDuration;
    // matchManagerEpochDuration;
    // matchManagerMatchDuration;
    // finalTime;
    pub Bytes32Field,  // initialHash;
    pub AddressField,  // machineAddress;
    pub String32Field, // currentState
);

#[derive(Serialize, Debug)]
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
        _post_payload: &Option<String>,
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
        trace!(
            "Context for revealmock (index {}) {:?}",
            instance.index,
            ctx
        );

        match ctx.current_state.as_ref() {
            // TO-DO: RevealMock should never be in these states. Add warning.
            "CommitPhase" | "RevealPhase" => {
                return Ok(Reaction::Idle);
            }

            "MatchManagerPhase" => {
                let match_manager_instance = instance.sub_instances.get(0).ok_or(Error::from(
                    ErrorKind::InvalidContractState(format!(
                        "There is no match manager instance {}",
                        ctx.current_state
                    )),
                ))?;

                // if state is MatchManagerPhase, control goes to matchmanager
                return MatchManager::react(
                    match_manager_instance,
                    archive,
                    &None,
                    &Default::default(),
                );
            }

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
        let parsed: RevealMockCtxParsed =
            serde_json::from_str(&instance.json_data).chain_err(|| {
                format!(
                    "Could not parse match instance json_data: {}",
                    &instance.json_data
                )
            })?;
        let ctx: RevealMockCtx = parsed.into();
        let json_data = serde_json::to_string(&ctx).unwrap();

        // get context (state) of the sub instances

        let mut pretty_sub_instances: Vec<Box<state::Instance>> = vec![];

        for sub in &instance.sub_instances {
            pretty_sub_instances.push(Box::new(
                MatchManager::get_pretty_instance(sub, archive, &Default::default()).unwrap(),
            ))
        }

        let pretty_instance = state::Instance {
            name: "RevealMock".to_string(),
            concern: instance.concern.clone(),
            index: instance.index,
            service_status: archive.get_service("RevealMock".into()),
            json_data: json_data,
            sub_instances: pretty_sub_instances,
        };

        return Ok(pretty_instance);
    }
}
