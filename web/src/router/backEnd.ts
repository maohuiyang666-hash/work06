import { RouteRecordRaw } from 'vue-router';
import pinia from '/@/stores/index';
import { useUserInfo } from '/@/stores/userInfo';
import { useRequestOldRoutes } from '/@/stores/requestOldRoutes';
import { Session } from '/@/utils/storage';
import { NextLoading } from '/@/utils/loading';
import { dynamicRoutes, notFoundAndNoPower } from '/@/router/route';
import { formatTwoStageRoutes, formatFlatteningRoutes, router } from '/@/router/index';
import { useRoutesList } from '/@/stores/routesList';
import { useTagsViewRoutes } from '/@/stores/tagsViewRoutes';
import { useMenuApi } from '/@/api/menu/index';
import { handleMenu } from '../utils/menu';
import { BtnPermissionStore } from '/@/plugin/permission/store.permission';
import { SystemConfigStore } from '/@/stores/systemConfig';
import { useDeptInfoStore } from '/@/stores/modules/dept';
import { DictionaryStore } from '/@/stores/dictionary';
import { useFrontendMenuStore } from '/@/stores/frontendMenu';
import { toRaw } from 'vue';

const menuApi = useMenuApi();

const layouModules: any = import.meta.glob('../layout/routerView/*.{vue,tsx}');
const viewsModules: any = import.meta.glob('../views/**/*.{vue,tsx}');
const greatDream: any = import.meta.glob('@great-dream/**/*.{vue,tsx}');

/**
 * 获取目录下的 .vue、.tsx 全部文件
 * @method import.meta.glob
 * @link 参考：https://cn.vitejs.dev/guide/features.html#json
 */
const dynamicViewsModules: Record<string, Function> = Object.assign({}, { ...layouModules }, { ...viewsModules }, { ...greatDream });

let backEndControlRoutesInitPromise: Promise<boolean> | null = null;

const hasBackEndRoutesMounted = () => {
	return router.hasRoute('/');
};

/**
 * 后端控制路由：初始化方法，防止刷新时路由丢失
 * @method NextLoading 界面 loading 动画开始执行
 * @method useUserInfo().setUserInfos() 触发初始化用户信息 pinia
 * @method useRequestOldRoutes().setRequestOldRoutes() 存储接口原始路由（未处理component），根据需求选择使用
 * @method setAddRoute 添加动态路由
 * @method setFilterMenuAndCacheTagsViewRoutes 设置路由到 vuex routesList 中（已处理成多级嵌套路由）及缓存多级嵌套数组处理后的一维数组
 */
export async function initBackEndControlRoutes() {
	if (!Session.get('token')) return false;
	if (hasBackEndRoutesMounted() && dynamicRoutes[0].children.length > 0) {
		await setFilterMenuAndCacheTagsViewRoutes();
		return true;
	}
	if (backEndControlRoutesInitPromise) return await backEndControlRoutesInitPromise;
	backEndControlRoutesInitPromise = (async () => {
		if (window.nextLoading === undefined) NextLoading.start();
		await useUserInfo().getApiUserInfo();
		const res = await getBackEndControlRoutes();
		await useRequestOldRoutes().setRequestOldRoutes(res.data);
		const { frameIn } = handleMenu(res.data);
		dynamicRoutes[0].children = await backEndComponent(frameIn);
		await setAddRoute();
		await setFilterMenuAndCacheTagsViewRoutes();
		return true;
	})();
	try {
		return await backEndControlRoutesInitPromise;
	} finally {
		backEndControlRoutesInitPromise = null;
	}
}

export async function setRouters() {
	const { frameInRoutes, frameOutRoutes } = await useFrontendMenuStore().getRouter();
	const frameInRouter = toRaw(frameInRoutes);
	const frameOutRouter = toRaw(frameOutRoutes);
	dynamicRoutes[0].children = frameInRouter;
	dynamicRoutes.forEach((item: any) => {
		router.addRoute(item);
	});
	frameOutRouter.forEach((item: any) => {
		router.addRoute(item);
	});
	const storesRoutesList = useRoutesList(pinia);
	storesRoutesList.setRoutesList([...dynamicRoutes[0].children, ...frameOutRouter]);
	const storesTagsView = useTagsViewRoutes(pinia);
	storesTagsView.setTagsViewRoutes([...dynamicRoutes[0].children, ...frameOutRouter]);
}

/**
 * 设置路由到 vuex routesList 中（已处理成多级嵌套路由）及缓存多级嵌套数组处理后的一维数组
 * @description 用于左侧菜单、横向菜单的显示
 * @description 用于 tagsView、菜单搜索中：未过滤隐藏的(isHide)
 */
export async function setFilterMenuAndCacheTagsViewRoutes() {
	const storesRoutesList = useRoutesList(pinia);
	await storesRoutesList.setRoutesList(dynamicRoutes[0].children as any);
	await setCacheTagsViewRoutes();
}

/**
 * 缓存多级嵌套数组处理后的一维数组
 * @description 用于 tagsView、菜单搜索中：未过滤隐藏的(isHide)
 */
export async function setCacheTagsViewRoutes() {
	const storesTagsView = useTagsViewRoutes(pinia);
	await storesTagsView.setTagsViewRoutes(formatTwoStageRoutes(formatFlatteningRoutes(dynamicRoutes))[0].children);
}

/**
 * 处理路由格式及添加捕获所有路由或 404 Not found 路由
 * @description 替换 dynamicRoutes（/@/router/route）第一个顶级 children 的路由
 * @returns 返回替换后的路由数组
 */
export function setFilterRouteEnd() {
	let filterRouteEnd: any = formatTwoStageRoutes(formatFlatteningRoutes(dynamicRoutes));
	filterRouteEnd[0].children = [...filterRouteEnd[0].children, ...notFoundAndNoPower];
	return filterRouteEnd;
}

/**
 * 添加动态路由
 * @method router.addRoute
 * @description 此处循环为 dynamicRoutes（/@/router/route）第一个顶级 children 的路由一维数组，非多级嵌套
 * @link 参考：https://next.router.vuejs.org/zh/api/#addroute
 */
export async function setAddRoute() {
	setFilterRouteEnd().forEach((route: RouteRecordRaw) => {
		router.addRoute(route);
	});
}

/**
 * 请求后端路由菜单接口
 * @description isRequestRoutes 为 true，则开启后端控制路由
 * @returns 返回后端路由菜单数据
 */
export function getBackEndControlRoutes() {
	BtnPermissionStore().getBtnPermissionStore();
	SystemConfigStore().getSystemConfigs();
	useDeptInfoStore().requestDeptInfo();
	DictionaryStore().getSystemDictionarys();
	return menuApi.getSystemMenu();
}

/**
 * 重新请求后端路由菜单接口
 * @description 用于菜单管理界面刷新菜单（未进行测试）
 * @description 路径：/src/views/system/menu/component/addMenu.vue
 */
export function setBackEndControlRefreshRoutes() {
	getBackEndControlRoutes();
}

/**
 * 后端路由 component 转换
 * @param routes 后端返回的路由表数组
 * @returns 返回处理成函数后的 component
 */
export function backEndComponent(routes: any) {
	if (!routes) return;
	return routes.map((item: any) => {
		if (item.component) item.component = dynamicImport(dynamicViewsModules, item.component as string);
		if (item.is_catalog) {
			item.component = dynamicImport(dynamicViewsModules, 'layout/routerView/parent');
		}
		if (item.is_link) {
			if (item.is_iframe) {
				item.component = dynamicImport(dynamicViewsModules, 'layout/routerView/iframes');
			} else {
				item.component = dynamicImport(dynamicViewsModules, 'layout/routerView/link');
			}
		} else if (item.is_iframe) {
			item.meta.isLink = item.link_url;
			item.component = dynamicImport(dynamicViewsModules, 'layout/routerView/link.vue');
		}
		item.children && backEndComponent(item.children);
		return item;
	});
}

/**
 * 后端路由 component 转换函数
 * @param dynamicViewsModules 获取目录下的 .vue、.tsx 全部文件
 * @param component 当前要处理项 component
 * @returns 返回处理成函数后的 component
 */
export function dynamicImport(dynamicViewsModules: Record<string, Function>, component: string) {
	const keys = Object.keys(dynamicViewsModules);
	const matchKeys = keys.filter((key) => {
		const k = key.replace(/..\/views|../, '');
		const k0 = k.replace('ode_modules/@great-dream/', '');
		const k1 = k0.replace('/plugins', '');
		const newComponent = component.replace('plugins/', '');
		return k1.startsWith(`${newComponent}`) || k1.startsWith(`/${newComponent}`);
	});
	if (matchKeys?.length === 1) {
		const matchKey = matchKeys[0];
		return dynamicViewsModules[matchKey];
	}
	if (matchKeys?.length > 1) {
		return false;
	}
}
