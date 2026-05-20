# Edge Cases Matrix

| ID | Edge Case | Primary Tests | Status |
| --- | --- | --- | --- |
| EDGE-ZAP-001 | ZapIn zero amount rejects before routing. | `test_zapIn_zeroAmount_reverts` (BasaltZapIn.t.sol) | Covered. |
| EDGE-ZAP-002 | ZapIn below minimum deposit rejects after live oracle and GMX reads. | `test_zapIn_dustAmount_revertsWithBelowMinimumDeposit` (BasaltZapIn.t.sol) | Covered. |
| EDGE-ZAP-003 | ZapIn missing execution fee rejects after minimum deposit check. | `test_zapIn_zeroMsgValue_reverts` (BasaltZapIn.t.sol) | Covered. |
| EDGE-ZAP-004 | ZapIn GMX callback only accepts the configured GMX deposit handler. | `test_finalizeDeposit_asStranger_reverts` (DepositHandler.t.sol) | Covered; negative auth expansion pending. |
| EDGE-ZAPOUT-001 | ZapOut zero shares rejects. | `test_zapOut_zeroAmount_reverts` (BasaltZapOut.t.sol) | Covered. |
| EDGE-ZAPOUT-002 | ZapOut slippage below minimum rejects before share pull. | `test_zapOut_slippageBelowMin_reverts` (BasaltZapOut.t.sol) | Covered. |
| EDGE-GMUNWRAP-001 | GmUnwrapper rejects missing execution fee. | `test_unwrap_zeroMsgValue_reverts` (BasaltGmUnwrapper.t.sol) | Covered. |
| EDGE-ASYNC-001 | AsyncRecovery cannot unstuck before deadline plus grace. | `test_unstuckPending_beforeDeadline_reverts` (AsyncRecoveryHandler.t.sol) | Covered. |
| EDGE-CORE-001 | UniversalCall rejects unauthorized initiators. | `test_universalCall_asStranger_reverts` (VaultCore.t.sol) | Covered. |
| EDGE-CORE-002 | Factory rejects zero owner vault creation. | Not implemented | No dedicated zero-owner revert test exists. |
| EDGE-CORE-003 | Factory address-book cooldown blocks clone creation. | `invariant_invFac001_cooldownBlocksCreation` (InvariantFeeAccounting.t.sol) | Covered via invariant suite. |
| EDGE-ORACLE-001 | Sequencer down rejects. | `test_oracle_sequencerDown_reverts` (OracleManipulation.t.sol) | Covered. |
| EDGE-ORACLE-002 | Stale oracle rejects. | `test_oracle_stalePrice_reverts` (OracleManipulation.t.sol) | Covered. |
| EDGE-ORACLE-003 | Oracle price above cap rejects. | `test_oracle_priceAboveCeiling_reverts` (OracleManipulation.t.sol) | Covered. |
| EDGE-FORK-001 | Repeated vault scenarios remain cache-safe by using fixed actor pools. | `testE2E_scenario10StepsDeterministic` (ScenarioHappyPath10Fork.t.sol) | Covered. |

Open expansion items: max amount limits, ETH residue sweeps, and full real-vault ZapOut success/cancel branches depend on the `zap-product` and full Dolomite setup work.
