import React, { useState, useEffect } from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import "./styles/tokens.css";
import { AuthProvider, useAuth } from "./hooks/useAuth";
import LoginPage from "./pages/Login";
import ConsentPage from "./pages/Consent";
import MainPage from "./pages/Main";

class ErrorBoundary extends React.Component<{ children: React.ReactNode }, { error: string | null }> {
    constructor(props: any) { super(props); this.state = { error: null }; }
    static getDerivedStateFromError(e: Error) { return { error: e.message }; }
    render() {
        if (this.state.error) return (
            <div style={{ padding: 32, fontFamily: "monospace", color: "red", background: "#fff", whiteSpace: "pre-wrap" }}>
                <b>Render error:</b>{"\n"}{this.state.error}
            </div>
        );
        return this.props.children;
    }
}

function AppRoutes() {
    const { session, loading } = useAuth();
    const [theme, setTheme] = useState<"light" | "dark">(() => {
        const stored = localStorage.getItem("wp-theme");
        return (stored === "dark" || stored === "light") ? stored : "light";
    });

    useEffect(() => {
        document.documentElement.setAttribute("data-theme", theme);
        localStorage.setItem("wp-theme", theme);
    }, [theme]);

    const toggleTheme = () => setTheme(t => t === "light" ? "dark" : "light");

    if (loading) return <div style={{ background: "var(--bg)", height: "100vh" }} />;
    if (!session) return <Routes><Route path="*" element={<LoginPage />} /></Routes>;

    return (
        <Routes>
            <Route path="/" element={<MainPage theme={theme} onToggleTheme={toggleTheme} />} />
            <Route path="/consent" element={<ConsentPage />} />
            <Route path="*" element={<Navigate to="/" />} />
        </Routes>
    );
}

// Apply stored theme before first render to prevent flash
const storedTheme = localStorage.getItem("wp-theme") ?? "light";
document.documentElement.setAttribute("data-theme", storedTheme);

ReactDOM.createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
        <ErrorBoundary>
            <AuthProvider>
                <BrowserRouter>
                    <AppRoutes />
                </BrowserRouter>
            </AuthProvider>
        </ErrorBoundary>
    </React.StrictMode>
);