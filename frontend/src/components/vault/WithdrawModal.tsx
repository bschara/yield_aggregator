import { useState } from "react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { buildWithdrawPayload } from "@/lib/aptos";

interface WithdrawModalProps {
  onClose: () => void;
  onSuccess: () => void;
}

export function WithdrawModal({ onClose, onSuccess }: WithdrawModalProps) {
  const { signAndSubmitTransaction } = useWallet();
  const [objAddr, setObjAddr] = useState("");
  const [status, setStatus] = useState<"idle" | "pending" | "success" | "error">("idle");
  const [errMsg, setErrMsg] = useState("");

  async function handleWithdraw() {
    if (!objAddr.trim()) return;
    setStatus("pending");
    try {
      const payload = buildWithdrawPayload(objAddr.trim());
      await signAndSubmitTransaction({ data: payload });
      setStatus("success");
      setTimeout(() => { onSuccess(); onClose(); }, 1500);
    } catch (e) {
      setErrMsg(e instanceof Error ? e.message : "Transaction failed");
      setStatus("error");
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 w-full max-w-sm mx-4">
        <h2 className="text-lg font-semibold text-white mb-1">Withdraw APT</h2>
        <p className="text-xs text-gray-500 mb-4">
          Enter your deposit object address to burn shares and receive APT.
        </p>

        <label className="block text-xs text-gray-500 mb-1">Deposit Object Address</label>
        <input
          type="text"
          value={objAddr}
          onChange={(e) => setObjAddr(e.target.value)}
          placeholder="0x..."
          className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm font-mono focus:outline-none focus:border-brand-500 mb-4"
        />

        {status === "error" && (
          <p className="text-red-400 text-xs mb-3">{errMsg}</p>
        )}
        {status === "success" && (
          <p className="text-green-400 text-xs mb-3">Withdrawal submitted!</p>
        )}

        <div className="flex gap-2">
          <button
            onClick={onClose}
            className="flex-1 py-2 rounded-lg bg-gray-800 hover:bg-gray-700 text-gray-300 text-sm transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleWithdraw}
            disabled={status === "pending" || !objAddr.trim()}
            className="flex-1 py-2 rounded-lg bg-brand-600 hover:bg-brand-700 disabled:opacity-50 text-white text-sm transition-colors"
          >
            {status === "pending" ? "Signing…" : "Withdraw"}
          </button>
        </div>
      </div>
    </div>
  );
}
