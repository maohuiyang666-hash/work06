<template>
	<div class="layout-logo" v-if="setShowLogo" @click="onThemeConfigChange">
		<img :src="siteLogo" class="layout-logo-medium-img" />
		<div class="layout-logo-content">
			<span class="layout-logo-title">{{ getSystemConfig['login.site_title'] || themeConfig.globalTitle }}</span>
			<span class="layout-logo-env">{{ appEnvLabel }}</span>
		</div>
	</div>
	<div class="layout-logo-size" v-else @click="onThemeConfigChange">
		<img :src="siteLogo" class="layout-logo-size-img" />
	</div>
</template>

<script setup lang="ts" name="layoutLogo">
import { computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useThemeConfig } from '/@/stores/themeConfig';
import logoMini from '/@/assets/logo-mini.svg';
import { SystemConfigStore } from '/@/stores/systemConfig';
import _ from 'lodash-es';
import { getAppEnvLabel } from '/@/utils/baseUrl';

const storesThemeConfig = useThemeConfig();
const { themeConfig } = storeToRefs(storesThemeConfig);

const setShowLogo = computed(() => {
	let { isCollapse, layout } = themeConfig.value;
	return !isCollapse || layout === 'classic' || document.body.clientWidth < 1000;
});

const onThemeConfigChange = () => {
	if (themeConfig.value.layout === 'transverse') return false;
	themeConfig.value.isCollapse = !themeConfig.value.isCollapse;
};

const systemConfigStore = SystemConfigStore();
const { systemConfig } = storeToRefs(systemConfigStore);
const getSystemConfig = computed(() => {
	return systemConfig.value;
});

const siteLogo = computed(() => {
	if (!_.isEmpty(getSystemConfig.value['login.site_logo'])) {
		return getSystemConfig.value['login.site_logo'];
	}
	return logoMini;
});

const appEnvLabel = computed(() => {
	return getAppEnvLabel();
});
</script>

<style scoped lang="scss">
.layout-logo {
	width: 220px;
	height: 50px;
	display: flex;
	align-items: center;
	justify-content: center;
	box-shadow: rgb(0 21 41 / 2%) 0px 1px 4px;
	color: var(--el-color-primary);
	font-size: 16px;
	cursor: pointer;
	animation: logoAnimation 0.3s ease-in-out;

	&-content {
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
	}

	&-title {
		font-size: x-large;
		white-space: nowrap;
		display: inline-block;
	}

	&-env {
		flex-shrink: 0;
		padding: 2px 8px;
		border-radius: 999px;
		background: var(--el-color-primary-light-8);
		color: var(--el-color-primary);
		font-size: 12px;
		line-height: 18px;
	}

	&:hover {
		.layout-logo-title {
			color: var(--color-primary-light-2);
		}
	}

	&-medium-img {
		width: 40px;
		margin-right: 5px;
	}
}

.layout-logo-size {
	width: 100%;
	height: 50px;
	display: flex;
	cursor: pointer;
	animation: logoAnimation 0.3s ease-in-out;

	&-img {
		width: 40px;
		margin: auto;
	}

	&:hover {
		img {
			animation: logoAnimation 0.3s ease-in-out;
		}
	}
}
</style>
