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

#![warn(unused_extern_crates)]
pub mod dappmock;
pub mod r#match;
pub mod matchmanager;
pub mod reveal_commit;
pub mod revealmock;

extern crate configuration;
extern crate error;

#[macro_use]
extern crate serde_derive;
extern crate crypto;
extern crate hex;
#[macro_use]
extern crate log;
extern crate compute;
extern crate dispatcher;
extern crate ethabi;
extern crate ethereum_types;
extern crate logger_service;
extern crate transaction;

use ethereum_types::{Address, U256};

pub use compute::Partition;
pub use compute::MM;
pub use compute::{
    build_session_proof_key, build_session_read_key, build_session_run_key, build_session_step_key,
    cartesi_base, AccessOperation, NewSessionRequest, NewSessionResult, SessionGetProofRequest,
    SessionGetProofResult, SessionReadMemoryRequest, SessionReadMemoryResult, SessionRunRequest,
    SessionRunResult, SessionStepRequest, EMULATOR_METHOD_NEW, EMULATOR_METHOD_PROOF,
    EMULATOR_METHOD_READ, EMULATOR_METHOD_RUN, EMULATOR_METHOD_STEP, EMULATOR_SERVICE_NAME,
};
pub use compute::{VGCtx, VGCtxParsed, VG, win_by_deadline_or_idle};

pub use logger_service::{
    DownloadFileRequest, DownloadFileResponse, SubmitFileRequest, SubmitFileResponse, LOGGER_METHOD_DOWNLOAD,
    LOGGER_METHOD_SUBMIT, LOGGER_SERVICE_NAME,
};

pub use dappmock::DAppMock;
pub use matchmanager::MatchManager;
pub use r#match::{MachineTemplate, Match};
pub use reveal_commit::{Params, Payload, RevealCommit};
pub use revealmock::RevealMock;

#[derive(Debug)]
enum Role {
    Claimer,
    Challenger,
}

pub fn get_logger_response(
    archive: &dispatcher::Archive,
    service: String,
    key: String,
    method: String,
    request: Vec<u8>
) -> error::Result<Vec<u8>> {
    let raw_response = archive
        .get_response(
            service.clone(),
            key.clone(),
            method.clone(),
            request.clone()
        )?
        .map_err(|_| {
            error::Error::from(error::ErrorKind::ArchiveInvalidError(
                service.clone(),
                key.clone(),
                method.clone()
            ))
        })?;

    match method.as_ref() {
        LOGGER_METHOD_SUBMIT => {
            let response: SubmitFileResponse = raw_response.clone().into();
            if response.status == 0 {
                Ok(raw_response)
            }
            else {
                error!("Fail to get logger response, status: {}", response.status);
                Err(error::Error::from(error::ErrorKind::ArchiveMissError(
                    service, key, method, request,
                )))
            }
        },
        LOGGER_METHOD_DOWNLOAD => {
            let response: DownloadFileResponse = raw_response.clone().into();
            if response.status == 0 {
                Ok(raw_response)
            }
            else {
                error!("Fail to get logger response, status: {}", response.status);
                Err(error::Error::from(error::ErrorKind::ArchiveMissError(
                    service, key, method, request,
                )))
            }
        },
        _ => {
            error!("Unknown logger method {} received, shouldn't happen!", method);
            Err(error::Error::from(error::ErrorKind::ArchiveInvalidError(
                service,
                key,
                method
            )))
        }
    }
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
