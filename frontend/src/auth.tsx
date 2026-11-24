import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { Navigate, useLocation } from "react-router";
import { get, post, type Me } from "./api";
import { PageLoading } from "./ui";

interface AuthState {
  me: Me | null;
  loading: boolean;
  refresh: () => Promise<void>;
  setMe: (me: Me | null) => void;
  logout: () => Promise<void>;
}

const AuthCtx = createContext<AuthState>(null!);
export const useAuth = () => useContext(AuthCtx);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(true);
  const refresh = useCallback(async () => {
    try {
      setMe(await get<Me>("/auth/me"));
    } catch {
      setMe(null);
    } finally {
      setLoading(false);
    }
  }, []);
  const logout = useCallback(async () => {
    await post("/auth/logout");
    setMe(null);
  }, []);
  useEffect(() => { refresh(); }, [refresh]);
  return <AuthCtx.Provider value={{ me, loading, refresh, setMe, logout }}>{children}</AuthCtx.Provider>;
}

export function RequireAuth({ children, admin }: { children: ReactNode; admin?: boolean }) {
  const { me, loading } = useAuth();
  const location = useLocation();
  if (loading) return <PageLoading />;
  if (!me) return <Navigate to={`/login?next=${encodeURIComponent(location.pathname + location.search)}`} replace />;
  if (admin && me.role !== "ADMIN") return <Navigate to="/" replace />;
  return <>{children}</>;
}
