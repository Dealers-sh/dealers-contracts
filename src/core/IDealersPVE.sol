// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IDealersPVE {
    // =============================================================
    //                            ENUMS
    // =============================================================

    enum GameChoice { DEAL, THREATEN, BAIL }
    enum GameOutcome { WIN, TIE, LOSS }
    enum HustleType { BUY, SELL }

    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct PveStats {
        uint32 wins;
        uint32 losses;
        uint32 ties;
        uint32 dealChoices;
        uint32 threatenChoices;
        uint32 bailChoices;
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function getDealerPveStats(uint256 tokenId) external view returns (PveStats memory);

    function canPlay(uint256 tokenId) external view returns (bool isPlayable, uint8 reason);

    function previewHustle(uint256 tokenId, uint256 drugId, uint256 amount) external view returns (
        int16 winRep,
        int16 tieRep,
        int16 lossRep,
        uint256 cashValueOnSell,
        uint256 cashCostOnBuy
    );

    /// @notice Raw mapping getter — returns tuple (for Claims compatibility)
    function dealerPveStats(uint256 tokenId) external view returns (
        uint32 wins,
        uint32 losses,
        uint32 ties,
        uint32 dealChoices,
        uint32 threatenChoices,
        uint32 bailChoices
    );

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    function playGame(
        uint256 tokenId,
        uint8 choice,
        HustleType hustleType,
        uint256 drugId,
        uint256 amount
    ) external;
}
