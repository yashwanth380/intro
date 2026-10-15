/**
 * CAMPUS CONNECT — SUPABASE BACKEND CONFIGURATION & CLIENT WRAPPER
 * 
 * Provides official Supabase client initialization, secure key management (file or localStorage),
 * connection health testing, and session management for the vanilla JavaScript frontend.
 */

(function (window) {
  'use strict';

  // Default configuration placeholders.
  // Paste your project values below or use the in-app "Backend Settings" modal to configure in browser.
  const DEFAULT_CONFIG = {
    SUPABASE_URL: '',
    SUPABASE_ANON_KEY: ''
  };

  const STORAGE_KEY_URL = 'campus_connect_sb_url';
  const STORAGE_KEY_KEY = 'campus_connect_sb_key';

  const SupabaseBridge = {
    client: null,

    getConfig() {
      const storedUrl = localStorage.getItem(STORAGE_KEY_URL);
      const storedKey = localStorage.getItem(STORAGE_KEY_KEY);

      const winConfig = window.CAMPUS_CONNECT_CONFIG || {};

      const url = (storedUrl || winConfig.SUPABASE_URL || DEFAULT_CONFIG.SUPABASE_URL || '').trim();
      const key = (storedKey || winConfig.SUPABASE_ANON_KEY || DEFAULT_CONFIG.SUPABASE_ANON_KEY || '').trim();

      return { url, key };
    },

    isConfigured() {
      const { url, key } = this.getConfig();
      return Boolean(url && key && url.startsWith('http') && key.length > 20);
    },

    init() {
      const { url, key } = this.getConfig();

      if (!this.isConfigured()) {
        this.client = null;
        console.info('[CampusConnect Backend] Supabase credentials not set. Operating in Offline Demo Mode.');
        return null;
      }

      if (typeof window.supabase === 'undefined' || typeof window.supabase.createClient !== 'function') {
        console.error('[CampusConnect Backend] Supabase JS SDK not loaded. Ensure CDN is accessible.');
        this.client = null;
        return null;
      }

      try {
        this.client = window.supabase.createClient(url, key, {
          auth: {
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: true,
            storage: window.localStorage
          }
        });
        console.info('[CampusConnect Backend] Supabase client initialized successfully.');
        return this.client;
      } catch (err) {
        console.error('[CampusConnect Backend] Failed to initialize Supabase client:', err);
        this.client = null;
        return null;
      }
    },

    getClient() {
      if (!this.client && this.isConfigured()) {
        return this.init();
      }
      return this.client;
    },

    saveCredentials(url, anonKey) {
      const trimmedUrl = (url || '').trim();
      const trimmedKey = (anonKey || '').trim();

      if (trimmedUrl) {
        localStorage.setItem(STORAGE_KEY_URL, trimmedUrl);
      } else {
        localStorage.removeItem(STORAGE_KEY_URL);
      }

      if (trimmedKey) {
        localStorage.setItem(STORAGE_KEY_KEY, trimmedKey);
      } else {
        localStorage.removeItem(STORAGE_KEY_KEY);
      }

      this.init();
      window.dispatchEvent(new CustomEvent('supabase:config-changed', {
        detail: { isConfigured: this.isConfigured() }
      }));
    },

    clearCredentials() {
      localStorage.removeItem(STORAGE_KEY_URL);
      localStorage.removeItem(STORAGE_KEY_KEY);
      this.client = null;
      window.dispatchEvent(new CustomEvent('supabase:config-changed', {
        detail: { isConfigured: false }
      }));
    },

    async testConnection() {
      const client = this.getClient();
      if (!client) {
        return { ok: false, message: 'Supabase client is not configured.' };
      }

      try {
        const { data, error } = await client.from('communities').select('id, name').limit(1);
        if (error) {
          return { ok: false, message: error.message };
        }
        return { ok: true, message: 'Connected successfully to Supabase database!' };
      } catch (err) {
        return { ok: false, message: err.message || 'Network error connecting to Supabase.' };
      }
    }
  };

  window.SupabaseBridge = SupabaseBridge;
})(window);
