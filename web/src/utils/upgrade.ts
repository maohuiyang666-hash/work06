import axios from 'axios';
import * as process from 'process';
import { Local, Session } from '/@/utils/storage';
import { ElNotification } from 'element-plus';
import fs from 'fs';

const IS_SHOW_UPGRADE_SESSION_KEY = 'isShowUpgrade';
const VERSION_KEY = 'DVADMIN3_VERSION';
const VERSION_FILE_NAME = 'version-build';

const META_ENV = import.meta.env;

export function showUpgrade() {
	const isShowUpgrade = Session.get(IS_SHOW_UPGRADE_SESSION_KEY) ?? false;
	if (isShowUpgrade) {
		Session.remove(IS_SHOW_UPGRADE_SESSION_KEY);
		ElNotification({
			title: '新版本升级',
			message: '检测到系统新版本，正在更新中！不用担心，更新很快的哦！',
			type: 'success',
			duration: 5000,
		});
	}
}

export async function checkVersion() {
	if (META_ENV.MODE === 'development') {
		return;
	}
	await axios.get(`${META_ENV.VITE_PUBLIC_PATH}${VERSION_FILE_NAME}?t=${new Date().getTime()}`).then((res) => {
		const { status, data } = res || {};
		if (status === 200) {
			const localVersion = Local.get(VERSION_KEY);
			Local.set(VERSION_KEY, data);
			if (localVersion && localVersion !== data) {
				Session.set(IS_SHOW_UPGRADE_SESSION_KEY, true);
				window.location.reload();
			}
		}
	});
}

export function generateVersionFile(appEnv = 'dev') {
	const packageVersion = META_ENV?.npm_package_version ?? process.env?.npm_package_version;
	const version = `${appEnv}:${packageVersion}.${new Date().getTime()}`;
	fs.writeFileSync(`public/${VERSION_FILE_NAME}`, version);
}
