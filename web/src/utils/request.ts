import axios, { AxiosInstance, AxiosRequestConfig } from 'axios';
import { ElMessage, ElMessageBox } from 'element-plus';
import { Session } from '/@/utils/storage';
import qs from 'qs';
import { getApiBaseURL } from '/@/utils/baseUrl';

const service: AxiosInstance = axios.create({
	baseURL: getApiBaseURL().replace(/\/$/, ''),
	timeout: 50000,
	headers: { 'Content-Type': 'application/json' },
	paramsSerializer: {
		serialize(params: Record<string, unknown>) {
			return qs.stringify(params, { allowDots: true });
		},
	},
});

service.interceptors.request.use(
	(config: AxiosRequestConfig) => {
		if (Session.get('token')) {
			config.headers!['Authorization'] = `${Session.get('token')}`;
		}
		return config;
	},
	(error: any) => {
		return Promise.reject(error);
	}
);

service.interceptors.response.use(
	(response: any) => {
		const res = response.data;
		if (res.code && res.code !== 0) {
			if (res.code === 401 || res.code === 4001) {
				Session.clear();
				window.location.href = '/';
				ElMessageBox.alert('你已被登出，请重新登录', '提示', {})
					.then(() => {})
					.catch(() => {});
			}
			return Promise.reject(service.interceptors.response);
		}
		return response.data;
	},
	(error: any) => {
		if (error.message.indexOf('timeout') != -1) {
			ElMessage.error('网络超时');
		} else if (error.message == 'Network Error') {
			ElMessage.error('网络连接错误');
		} else {
			if (error.response.data) ElMessage.error(error.response.statusText);
			else ElMessage.error('接口路径找不到');
		}
		return Promise.reject(error);
	}
);

export default service;
