import React, { createContext, useContext, useState, useCallback, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

interface Session { user_id: string; email: string; }
interface AuthCtx { session: Session | null; loading: boolean; login: (email: string, pass: string) => Promise<void>; logout: () => Promise<void>; }

const AuthContext = createContext<AuthCtx | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    invoke<Session | null>("get_session")
      .then(s => { if (s) setSession(s); })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    const s = await invoke<Session>("login", { email, password });
    setSession(s);
  }, []);

  const logout = useCallback(async () => {
    await invoke("logout");
    setSession(null);
  }, []);

  return <AuthContext.Provider value={{ session, loading, login, logout }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be inside AuthProvider");
  return ctx;
}
