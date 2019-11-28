// Arbritration DLib is the combination of the on-chain protocol and off-chain
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


#![warn(unused_extern_crates)]
pub mod r#match;
pub mod matchmanager;
pub mod revealmock;
pub mod dappmock;
pub mod reveal_commit;

extern crate configuration;
extern crate error;

#[macro_use]
extern crate serde_derive;
#[macro_use]
extern crate log;
extern crate dispatcher;
extern crate ethabi;
extern crate ethereum_types;
extern crate transaction;
extern crate emulator_interface;
extern crate compute;
extern crate logger_service;

use ethereum_types::{Address, U256};

pub use compute::MM;
pub use compute::Partition;
pub use compute::{VG, VGCtx, VGCtxParsed};
pub use compute::{
    cartesi_base, build_session_run_key, build_session_step_key, 
    build_session_read_key, build_session_proof_key,
    AccessOperation, NewSessionRequest, NewSessionResult,
    SessionRunRequest, SessionRunResult, SessionStepRequest,
    SessionReadMemoryRequest, SessionReadMemoryResult,
    SessionGetProofRequest, SessionGetProofResult,
    EMULATOR_SERVICE_NAME, EMULATOR_METHOD_NEW,
    EMULATOR_METHOD_RUN, EMULATOR_METHOD_STEP,
    EMULATOR_METHOD_READ, EMULATOR_METHOD_PROOF};
    
pub use logger_service::{
    DownloadFileRequest, SubmitFileRequest,
    LOGGER_SERVICE_NAME, LOGGER_METHOD_SUBMIT,
    LOGGER_METHOD_DOWNLOAD, Hash, FilePath};

pub use r#match::{Match, MachineTemplate};
pub use revealmock::RevealMock;
pub use dappmock::DAppMock;
pub use reveal_commit::{RevealCommit, Payload, Params};
pub use matchmanager::MatchManager;

#[derive(Debug)]
enum Role {
    Claimer,
    Challenger,
}

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// we need to have a proper way to construct machine ids.
// but this will only make real sense when we have the scripting
// language or some other means to construct a machine inside the
// blockchain.
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

pub fn build_machine_id(tournament_index: U256, player_address: &Address) -> String {
    return format!("{:x}:{}", player_address, tournament_index);
    //return "0000000000000000000000000000000000000000000000008888888888888888"
    //    .to_string();
}