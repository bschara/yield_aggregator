import { useState } from "react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { PageLayout } from "@/components/layout/PageLayout";
import { Card } from "@/components/common/Card";
import { Spinner } from "@/components/common/Spinner";
import { DepositModal } from "@/components/vault/DepositModal";
import { WithdrawModal } from "@/components/vault/WithdrawModal";
import { useVaultState } from "@/hooks/useVaultState";
import { useUserShares } from "@/hooks/useUserShares";
import { octasToApt } from "@/lib/aptos";

export function Portfolio() {
  const { connected, connect, wallets } = useWallet();
  const { data: vault, isLoading: vaultLoading } = useVaultState();
  const { data: userShares, isLoading: sharesLoading, refetch } = useUserShares();
  const [showDeposit, setShowDeposit] = useState(false);
  const [showWithdraw, setShowWithdraw] = useState(false);

  const petra = wallets?.find((w) => w.name === "Petra");

  const totalAssets = vault?.totalAssets ?? 0n;
  const shareSupply = vault?.shareSupply ?? 0n;
  const shares = userShares ?? 0n;

  const aptValue =
    shareSupply > 0n
      ? octasToApt((shares * totalAssets) / shareSupply)
      : 0;

  return (
    <PageLayout title="Portfolio">
      {!connected ? (
        <Card className="max-w-sm">
          <p className="text-sm text-gray-400 mb-4">
            Connect your Petra wallet to see your balance and interact with the vault.
          </p>
          <button
            onClick={() => petra && connect(petra.name)}
            className="w-full py-2 rounded-lg bg-brand-600 hover:bg-brand-700 text-white text-sm transition-colors"
          >
            Connect Petra
          </button>
        </Card>
      ) : (
        <div className="space-y-4 max-w-lg">
          <Card>
            <p className="text-xs text-gray-500 uppercase tracking-wider mb-3">Your Position</p>
            {sharesLoading || vaultLoading ? (
              <div className="flex items-center gap-2">
                <Spinner size={4} />
                <span className="text-sm text-gray-500">Loading…</span>
              </div>
            ) : (
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-xs text-gray-500">Shares</p>
                  <p className="text-xl font-semibold text-white">
                    {shares.toString()}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-gray-500">Estimated Value</p>
                  <p className="text-xl font-semibold text-white">
                    {aptValue.toFixed(4)} APT
                  </p>
                </div>
              </div>
            )}
          </Card>

          <div className="flex gap-3">
            <button
              onClick={() => setShowDeposit(true)}
              className="flex-1 py-2.5 rounded-lg bg-brand-600 hover:bg-brand-700 text-white text-sm font-medium transition-colors"
            >
              Deposit
            </button>
            <button
              onClick={() => setShowWithdraw(true)}
              className="flex-1 py-2.5 rounded-lg bg-gray-800 hover:bg-gray-700 text-gray-200 text-sm font-medium transition-colors"
            >
              Withdraw
            </button>
          </div>
        </div>
      )}

      {showDeposit && (
        <DepositModal onClose={() => setShowDeposit(false)} onSuccess={() => refetch()} />
      )}
      {showWithdraw && (
        <WithdrawModal onClose={() => setShowWithdraw(false)} onSuccess={() => refetch()} />
      )}
    </PageLayout>
  );
}
