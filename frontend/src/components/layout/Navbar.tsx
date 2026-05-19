import { NavLink } from "react-router-dom";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { usePolicyHealth } from "@/hooks/usePolicyScore";

const navItems = [
  { to: "/", label: "Dashboard" },
  { to: "/strategies", label: "Strategies" },
  { to: "/portfolio", label: "Portfolio" },
  { to: "/bridge", label: "Bridge" },
];

export function Navbar() {
  const { connect, disconnect, connected, account, wallets, notDetectedWallets } = useWallet();
  const { data: healthy } = usePolicyHealth();

  const petra =
    wallets.find((w) => w.name === "Petra") ??
    notDetectedWallets.find((w) => w.name === "Petra");

  return (
    <nav className="border-b border-gray-800 bg-gray-950/80 backdrop-blur sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 flex items-center justify-between h-14">
        <div className="flex items-center gap-6">
          <span className="text-white font-semibold text-sm tracking-wide">YieldAgg</span>
          <div className="flex gap-1">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === "/"}
                className={({ isActive }) =>
                  `px-3 py-1.5 rounded-lg text-sm transition-colors ${
                    isActive ? "bg-gray-800 text-white" : "text-gray-400 hover:text-gray-200"
                  }`
                }
              >
                {item.label}
              </NavLink>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1.5 text-xs text-gray-500">
            <span
              className={`w-2 h-2 rounded-full ${healthy ? "bg-green-500" : "bg-gray-600"}`}
            />
            Engine
          </div>

          {connected ? (
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-400 font-mono">
                {account?.address.toString().slice(0, 6)}…
                {account?.address.toString().slice(-4)}
              </span>
              <button
                onClick={() => disconnect()}
                className="text-xs px-3 py-1.5 rounded-lg bg-gray-800 hover:bg-gray-700 text-gray-300 transition-colors"
              >
                Disconnect
              </button>
            </div>
          ) : (
            <button
              onClick={() => petra && connect(petra.name)}
              className="text-xs px-3 py-1.5 rounded-lg bg-brand-600 hover:bg-brand-700 text-white transition-colors"
            >
              Connect Petra
            </button>
          )}
        </div>
      </div>
    </nav>
  );
}
