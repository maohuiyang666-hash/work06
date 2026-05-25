/// <reference types="vite/client" />

interface ImportMetaEnv {
	/** 环境标识：development / test / production / local_prod */
	readonly VITE_ENV: string;
	/** API 接口基础地址 */
	readonly VITE_API_URL: string;
	/** WebSocket 地址（为空则自动从 VITE_API_URL 推导） */
	readonly VITE_WS_URL: string;
	/** 开发服务器端口号 */
	readonly VITE_PORT: string;
	/** 是否自动打开浏览器 */
	readonly VITE_OPEN: string;
	/** 构建 public path */
	readonly VITE_PUBLIC_PATH: string;
	/** 构建输出目录 */
	readonly VITE_DIST_PATH: string;
	/** 是否启用按钮权限 */
	readonly VITE_PM_ENABLED: string;
	/** 应用标题后缀 */
	readonly VITE_APP_TITLE: string;
	/** npm package version */
	readonly npm_package_version: string;
}

interface ImportMeta {
	readonly env: ImportMetaEnv;
}

/** 构建时注入的全局环境常量 */
declare const __APP_ENV__: string;