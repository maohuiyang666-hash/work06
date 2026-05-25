/// <reference types="vite/client" />

interface ImportMetaEnv {
	readonly VITE_API_URL: string;
	readonly VITE_WS_URL: string;
	readonly VITE_PORT: string;
	readonly VITE_OPEN: string;
	readonly VITE_PUBLIC_PATH: string;
	readonly VITE_DIST_PATH: string;
	readonly VITE_PM_ENABLED: string;
	readonly VITE_APP_ENV: string;
}

interface ImportMeta {
	readonly env: ImportMetaEnv;
}
