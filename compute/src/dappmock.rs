use super::build_machine_id;
use super::configuration::Concern;
use super::dispatcher::{AddressField, Bytes32Field, String32Field, U256Field};
use super::dispatcher::{Archive, DApp, Reaction, SessionRunRequest};
use super::error::Result;
use super::error::*;
use super::ethabi::Token;
use super::ethereum_types::{Address, H256, U256};
use super::transaction;
use super::transaction::TransactionRequest;
use super::{Role, VG};
use vg::{VGCtx, VGCtxParsed};
use super::revealmock::{RevealMock, RevealMockCtx, RevealMockCtxParsed};

use std::time::{SystemTime, UNIX_EPOCH};

pub struct DAppMock();

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// these two structs and the From trait below shuld be
// obtained from a simple derive
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#[derive(Serialize, Deserialize)]
struct DAppMockCtxParsed(
    U256Field,  // revealIndex
);

#[derive(Debug)]
struct DAppMockCtx {
    reveal_index: U256,
}

impl From<DAppMockCtxParsed> for DAppMockCtx {
    fn from(parsed: DAppMockCtxParsed) -> DAppMockCtx {
        DappMockCtx {
            reveal_index: parsed.0.value,
            current_state: parsed.1.value,
        }
    }
}

impl DApp<()> for DappMockCtx {
    /// React to the compute contract, submitting solutions, confirming
    /// or challenging them when appropriate
    fn react(
        instance: &state::Instance,
        archive: &Archive,
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
            "DAppFinnished" => {
                return Ok(Reaction::Idle);
            }
            _ => {}
        };

        let revealmock_parsed: RevealMockCtxParsed =
            serde_json::from_str(&revealmock_instance.json_data)
                .chain_err(|| {
                    format!(
                        "Could not parse revealmock instance json_data: {}",
                        &revealmock_instance.json_data
                    )
                })?;
        let revealmock_ctx: RevealMockCtx = revealMock_parsed.into();

        match revealmock_ctx.current_state.as_ref() {
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
                    // revealMock is still active,
                    // pass control to the appropriate dapp
                    return RevealMock::react(revealmock_instance, archive, &());
                }
}
