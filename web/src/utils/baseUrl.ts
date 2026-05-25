import { pluginsAll } from '/@/views/plugins/index';

const metaEnv = import.meta.env;

const normalizeAppEnv = (value?: string) => {
	if (value === 'development') {
		return 'dev';
	}
	if (value === 'production') {
		return 'prod';
	}
	return value || 'dev';
};

const getRawApiBaseURL = () => {
	return (metaEnv.VITE_APP_API_BASE_URL || metaEnv.VITE_API_URL || '/api') as string;
};

const getRawWsBaseURL = () => {
	return (metaEnv.VITE_APP_WS_BASE_URL || '') as string;
};

const applyTenantBaseURL = (baseURL: string) => {
	let normalizedBaseURL = baseURL;
	const param = normalizedBaseURL.split('/')[3] || '';
	// @ts-ignore
	if (pluginsAll && pluginsAll.indexOf('dvadmin3-tenants-web') !== -1 && (!param || normalizedBaseURL.startsWith('/'))) {
		let host = normalizedBaseURL.split('/')[2];
		if (host) {
			const port = Number(normalizedBaseURL.split(':')[2] || 80);
			if (port === 80 || port === 443) {
				host = document.domain;
			} else {
				host = `${document.domain}:${port}`;
			}
			normalizedBaseURL = `${normalizedBaseURL.split('/')[0]}//${normalizedBaseURL.split('/')[1]}${host}/${param}`;
		} else {
			normalizedBaseURL = `${location.protocol}//${location.hostname}${location.port ? ':' : ''}${location.port}${normalizedBaseURL}`;
		}
	}
	return normalizedBaseURL;
};

const ensureTrailingSlash = (value: string) => {
	return value.endsWith('/') ? value : `${value}/`;
};

export const getAppEnv = () => {
	return normalizeAppEnv((metaEnv.VITE_APP_ENV || metaEnv.MODE) as string | undefined);
};

export const getAppEnvLabel = () => {
	const envLabel = metaEnv.VITE_APP_ENV_LABEL as string | undefined;
	if (envLabel) {
		return envLabel;
	}
	const appEnv = getAppEnv();
	if (appEnv === 'test') {
		return '测试';
	}
	if (appEnv === 'prod') {
		return '生产';
	}
	return '开发';
};

export const getApiBaseURL = () => {
	let baseURL = applyTenantBaseURL(getRawApiBaseURL());
	if (!baseURL.endsWith('/')) {
		baseURL += '/';
	}
	return baseURL;
};

export const getBaseURL = function (url: null | string = null, isHost: null | boolean = null) {
	let baseURL = getApiBaseURL();
	if (isHost && !baseURL.startsWith('http')) {
		baseURL = `${window.location.protocol}//${window.location.host}${baseURL}`;
	}
	if (url) {
		const regex = /^(http|https):\/\//;
		if (regex.test(url)) {
			return url;
		}
		return baseURL.replace(/\/$/, '') + '/' + url.replace(/^\//, '');
	}
	return baseURL;
};

export const getWsBaseURL = function () {
	const explicitWsBaseURL = getRawWsBaseURL();
	if (explicitWsBaseURL) {
		let wsBaseURL = ensureTrailingSlash(applyTenantBaseURL(explicitWsBaseURL));
		if (wsBaseURL.startsWith('http')) {
			wsBaseURL = wsBaseURL.replace('http', 'ws');
		}
		return wsBaseURL;
	}
	let baseURL = applyTenantBaseURL(getRawApiBaseURL());
	const param = baseURL.split('/')[3] || '';
	if (param !== '' || baseURL.startsWith('/')) {
		baseURL = `${location.protocol === 'https:' ? 'wss://' : 'ws://'}${location.hostname}${location.port ? ':' : ''}${location.port}${baseURL}`;
	}
	baseURL = ensureTrailingSlash(baseURL);
	if (baseURL.startsWith('http')) {
		baseURL = baseURL.replace('http', 'ws');
	}
	return baseURL;
};
