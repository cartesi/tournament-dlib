> :warning: The Cartesi team keeps working internally on the next version of this repository, following its regular development roadmap. Whenever there's a new version ready or important fix, these are published to the public source tree as new releases.

# Tournament Dlib

Tournament Dlib is the combination of the on-chain protocol and off-chain protocol that work together to create a decentralized tournament structure, in which an unlimited number of players can, using a commit and reveal scheme, submit a high score achieved in a generic game and reward the highest one. The dispute resolution runs in a decentralized way, with negligible cost for the onchain user. It is composed of a bracket system that divides players into matches - in which the highest score prevails. If a dispute occurs (i.e the lowest score thinks the other player is cheating), it is resolved using Cartesi's implementation of a [Verification Game](https://github.com/cartesi/arbitration-dlib/). The off-chain implementation navigates the tournament on-chain contracts, representing the player and taking the necessary actions (such as committing, revealing, verifying his opponent score and challenging it if invalid). The on-chain code is written in Solidity and the off-chain in Rust.


## Reveal Instantiator


A Reveal contract is instantiated when the DApp is created. It is responsible for the Commit/Reveal scheme of the tournament. It receives the durations of both phases in the instantiator, as well as informations about the game/dapp machine (i.e position of the output score drive, etc).

In the commit phase a player sends a generic hash value that represents the information he'll reveal later. Each player can commit as many hashes as he wants (as long as the commit phase is not over), but only the last one is considered.

The reveal phase is where the player has to commit to both the final_hash of the machine (after w/e he commited in the previous phase is executed) and the score. He also has to provide the siblings of the action log he commited in the previous phase and the siblings of the score output drive. The reveal function will check if the hash of the log commited is available, using the [Logger Service](https://github.com/cartesi/logger-dlib). It also checks if the score and the final_hash claimed by the player are compatible. The player can only reveal one commit.

The possible states of an instance of this contract are:

    //
    // +---+
    // |   |
    // +---+
    //   |
    //   | instantiate
    //   v
    // +--------------+
    // | CommitPhase  |
    // +--------------+
    //   |
    //   | commit/reveal (after commitDuration is over)
    //   v
    // +-------------+
    // | RevealPhase |
    // +-------------+
    //   |
    //   | endCommitAndReveal
    //   v
    // +------------------+
    // | CommitRevealDone |
    // +------------------+
    //

## MatchManager Instantiator

The MatchManager contract is responsible for organizing disputes in a way that the highest honest score is discovered in log2(n) epochs, where n = amount of challengers.
Players that think they might be the highest honest score (i.e continue to run the reference software after reveal phase) can register to this bracket system through the playNextEpoch function. The first bracket level is available to every player that successfully completed the reveal phase. After that, to register for a bracket phase (epoch) the user has to provide proof that he won a [match](https://github.com/cartesi/tournament-dlib#match-instantiator) in the previous epoch.

When a player spends the entirety of an epoch unmatched and there were no matches played in the previous epoch we can safely declare him as the winner of the entire tournament.

The possible states of an instance of this contract are:

    //
    // +---+
    // |   |
    // +---+
    //   |
    //   | instantiate
    //   v
    // +-----------------+
    // | WaitingMatches  |
    // +-----------------+
    //   |
    //   | claimWin
    //   v
    // +-------------+
    // | MatchesOver |
    // +-------------+
    //


## Match Instantiator

The matches are instantiated by the [Match Manager](https://github.com/cartesi/tournament-dlib#match-manager-instantiator) every time an instance has one unmatched player and another one registers to play the next epoch. The Match assumes that the claimer (whichever player has the highest score) is honest and opens up a window for the challenger to start a dispute. If the dispute is started, a [Verification Game](https://github.com/cartesi/arbitration-dlib/) is played to decide if the claimer was indeed being honest and had the highest score.


The possible states of an instance of this contract are:

    //
    //          +---+
    //          |   |
    //          +---+
    //            |
    //            | instantiate
    //            v
    //          +------------------+  claimVictoryByTime     +------------+
    //          | WaitingChallenge |------------------------>| ClaimerWon |
    //          +------------------+                         +------------+
    //            |
    //            | challengeHighScore
    //            v
    //          +------------------+
    //          | ChallengeStarted |
    //          +------------------+
    //            |
    //            | winByVG
    //            v
    //          +--------------------------+
    //          | ChallengerWon/ClaimerWon |
    //          +--------------------------+
    //

## Getting Started - on-chain code

### Install

Install dependencies

    npm install

Compile contracts with

    ./node_modules/.bin/truffle compile

Having a node listening to 8545, you can deploy using

    ./node_modules/.bin/truffle deploy


## Getting Started - off-chain code

### Install

Install rust
    curl https://sh.rustup.rs -sSf | sh

Add cargo to your path in `.bashrc`
    export PATH=$PATH:/home/user/.cargo/bin

Move to tournament dir:
    cd tournament

Build project:
    cargo build

## TODO

Protect against commit replication attacks
Optimize and recheck state transition

## Contributing

Thank you for your interest in Cartesi! Head over to our [Contributing Guidelines](CONTRIBUTING.md) for instructions on how to sign our Contributors Agreement and get started with Cartesi!

Please note we have a [Code of Conduct](CODE_OF_CONDUCT.md), please follow it in all your interactions with the project.

## Authors

* *Felipe Argento*
* *Stephen Chen*

## License

Note: This component currently has dependencies that are licensed under the GNU GPL, version 3, and so you should treat this component as a whole as being under the GPL version 3. But all Cartesi-written code in this component is licensed under the Apache License, version 2, or a compatible permissive license, and can be used independently under the Apache v2 license. After this component is rewritten, the entire component will be released under the Apache v2 license.
The arbitration d-lib repository and all contributions are licensed under
[GPL 3](https://www.gnu.org/licenses/gpl-3.0.en.html). Please review our [COPYING](COPYING) file.
