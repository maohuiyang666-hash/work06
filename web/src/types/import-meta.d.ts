interface ImportMetaEnv {
	readonly MODE: string;
	readonly VITE_APP_ENV?: string;
	readonly VITE_APP_ENV_LABEL?: string;
	readonly VITE_APP_API_BASE_URL?: string;
	readonly VITE_APP_WS_BASE_URL?: string;
	readonly VITE_API_URL?: string;
	readonly VITE_PUBLIC_PATH?: string;
}

interface ImportMeta {
	readonly env: ImportMetaEnv;
}
