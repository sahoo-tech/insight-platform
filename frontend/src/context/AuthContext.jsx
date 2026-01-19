import React, { createContext, useContext, useState, useEffect } from 'react';
import api from '../services/api';

const AuthContext = createContext(null);

// Module-scoped variable for promise deduplication
let refreshTokenPromise = null;

export function AuthProvider({ children }) {
    const [user, setUser] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const token = localStorage.getItem('access_token');
        if (token) {
            fetchCurrentUser();
        } else {
            setLoading(false);
        }
    }, []);

    const fetchCurrentUser = async () => {
        try {
            const response = await api.get('/auth/me');
            setUser(response.data);
        } catch (error) {
            localStorage.removeItem('access_token');
            localStorage.removeItem('refresh_token');
            setUser(null);
        } finally {
            setLoading(false);
        }
    };

    const login = async (email, password) => {
        const response = await api.post('/auth/login', { email, password });
        const { user, access_token, refresh_token } = response.data;

        localStorage.setItem('access_token', access_token);
        localStorage.setItem('refresh_token', refresh_token);
        setUser(user);

        return user;
    };

    const register = async (userData) => {
        const response = await api.post('/auth/register', userData);
        const { user, access_token, refresh_token } = response.data;

        localStorage.setItem('access_token', access_token);
        localStorage.setItem('refresh_token', refresh_token);
        setUser(user);

        return user;
    };

    const logout = async () => {
        try {
            await api.post('/auth/logout');
        } catch (error) {
            // Ignore logout errors
        }
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        setUser(null);
    };

    const refreshToken = async () => {
        const refresh = localStorage.getItem('refresh_token');
        if (!refresh) return false;

        // If a refresh is already in-flight, return the existing promise
        if (refreshTokenPromise) {
            return refreshTokenPromise;
        }
        
       // Create and store the refresh promise
        refreshTokenPromise = (async () => {
            try {
                const response = await api.post('/auth/refresh', { refresh_token: refresh });
                localStorage.setItem('access_token', response.data.access_token);
                return true;
            } catch (error) {
                logout();
                return false;
            } finally {
                // Clear the promise after resolution or rejection
                refreshTokenPromise = null;
            }
        })();

        return refreshTokenPromise;
    };

    const value = {
        user,
        loading,
        isAuthenticated: !!user,
        login,
        register,
        logout,
        refreshToken
    };

    return (
        <AuthContext.Provider value={value}>
            {children}
        </AuthContext.Provider>
    );
}

export function useAuth() {
    const context = useContext(AuthContext);
    if (!context) {
        throw new Error('useAuth must be used within AuthProvider');
    }
    return context;
}

export default AuthContext;
