import { BrowserRouter, Routes, Route } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AptosWalletAdapterProvider } from "@aptos-labs/wallet-adapter-react";
import { Navbar } from "@/components/layout/Navbar";
import { Dashboard } from "@/pages/Dashboard";
import { Strategies } from "@/pages/Strategies";
import { Portfolio } from "@/pages/Portfolio";
import { Bridge } from "@/pages/Bridge";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 5_000, retry: 1 },
  },
});

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AptosWalletAdapterProvider autoConnect={false} optInWallets={["Petra"]}>
        <BrowserRouter>
          <div className="min-h-screen bg-gray-950">
            <Navbar />
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/strategies" element={<Strategies />} />
              <Route path="/portfolio" element={<Portfolio />} />
              <Route path="/bridge" element={<Bridge />} />
            </Routes>
          </div>
        </BrowserRouter>
      </AptosWalletAdapterProvider>
    </QueryClientProvider>
  );
}
