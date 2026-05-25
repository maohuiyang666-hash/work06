<template>
	<div class="login-container flex z-10">
		<div class="login-left">
			<div class="login-left-logo">
				<img :src="siteLogo" />
				<div class="login-left-logo-text">
					<span>{{ getSystemConfig['login.site_title'] || getThemeConfig.globalViceTitle }}</span>
					<em>{{ envLabel }}</em>
				</div>
			</div>
		</div>
		<div class="login-right flex z-10">
			<div class="login-right-warp flex-margin">
				<div class="login-right-warp-mian">
					<div class="login-right-warp-main-title">
						<span>{{ getSystemConfig['login.site_name'] || getThemeConfig.globalViceTitleMsg }}</span>
						<br>
						<span>{{ userInfos.pwd_change_count === 0 ? '初次登录请修改密码' : '欢迎登录' }}</span>
					</div>
					<div class="login-right-warp-main-form">
						<div v-if="!state.isScan">
							<el-tabs v-model="state.tabsActiveName">
								<el-tab-pane :label="$t('message.label.changePwd')" name="changePwd" v-if="userInfos.pwd_change_count === 0">
									<ChangePwd />
								</el-tab-pane>
								<el-tab-pane :label="$t('message.label.one1')" name="account" v-else>
									<Account />
								</el-tab-pane>
								<el-tab-pane :label="$t('message.label.two2')" name="mobile">
									<Mobile />
								</el-tab-pane>
								<el-tab-pane :label="$t('message.label.two3')" name="scan">
									<scan />
								</el-tab-pane>
							</el-tabs>
						</div>
						<OAuth2 />
					</div>
				</div>
			</div>
		</div>

		<div class="login-authorization z-10">
			<p>Copyright © {{ getSystemConfig['login.copyright'] || '2021-2025 django-vue-admin.com' }} 版权所有</p>
			<p class="la-other" style="margin-top: 5px;">
				<a href="https://beian.miit.gov.cn" target="_blank">{{ getSystemConfig['login.keep_record'] || '晋ICP备18005113号-3' }}</a>
				|
				<a :href="getSystemConfig['login.help_url'] ? getSystemConfig['login.help_url'] : '#'" target="_blank">帮助</a>
				|
				<a :href="getSystemConfig['login.privacy_url'] ? getBaseURL(getSystemConfig['login.privacy_url']) : '#'">隐私</a>
				|
				<a :href="getSystemConfig['login.clause_url'] ? getBaseURL(getSystemConfig['login.clause_url']) : '#'">条款</a>
			</p>
		</div>
	</div>
	<div v-if="loginBg">
		<img :src="loginBg" class="loginBg fixed inset-0 z-1 w-full h-full" />
	</div>
</template>

<script setup lang="ts" name="loginIndex">
import { defineAsyncComponent, onMounted, reactive, computed, watch } from 'vue';
import { storeToRefs } from 'pinia';
import { useThemeConfig } from '/@/stores/themeConfig';
import { NextLoading } from '/@/utils/loading';
import logoMini from '/@/assets/logo-mini.svg';
import loginBg from '/@/assets/login-bg.png';
import { SystemConfigStore } from '/@/stores/systemConfig';
import { getAppEnvLabel, getBaseURL } from '/@/utils/baseUrl';
const Account = defineAsyncComponent(() => import('/@/views/system/login/component/account.vue'));
const Mobile = defineAsyncComponent(() => import('/@/views/system/login/component/mobile.vue'));
const Scan = defineAsyncComponent(() => import('/@/views/system/login/component/scan.vue'));
const ChangePwd = defineAsyncComponent(() => import('/@/views/system/login/component/changePwd.vue'));
const OAuth2 = defineAsyncComponent(() => import('/@/views/system/login/component/oauth2.vue'));

import _ from 'lodash-es';
import { useUserInfo } from '/@/stores/userInfo';
const { userInfos } = storeToRefs(useUserInfo());

const storesThemeConfig = useThemeConfig();
const { themeConfig } = storeToRefs(storesThemeConfig);
const state = reactive({
	tabsActiveName: 'account',
	isScan: false,
});

watch(
	() => userInfos.value.pwd_change_count,
	(val) => {
		if (val === 0) {
			state.tabsActiveName = 'changePwd';
		} else {
			state.tabsActiveName = 'account';
		}
	},
	{ deep: true, immediate: true }
);

const getThemeConfig = computed(() => {
	return themeConfig.value;
});

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

const envLabel = computed(() => {
	return getAppEnvLabel();
});

onMounted(() => {
	NextLoading.done();
});
</script>

<style scoped lang="scss">
.login-container {
	height: 100%;
	background: var(--el-color-white);

	.login-left {
		flex: 1;
		position: relative;
		background-color: rgba(211, 239, 255, 1);
		margin-right: 100px;

		.login-left-logo {
			display: flex;
			align-items: center;
			position: absolute;
			top: 50px;
			left: 80px;
			z-index: 1;
			animation: logoAnimation 0.3s ease;

			img {
				width: 52px;
				height: 52px;
			}

			.login-left-logo-text {
				display: flex;
				flex-direction: column;
				gap: 8px;

				span {
					margin-left: 10px;
					font-size: 24px;
					color: var(--el-color-primary);
				}

				em {
					margin-left: 10px;
					padding: 2px 10px;
					width: fit-content;
					border-radius: 999px;
					background: rgba(64, 158, 255, 0.12);
					color: var(--el-color-primary);
					font-size: 12px;
					font-style: normal;
				}
			}
		}

		.login-left-img {
			position: absolute;
			top: 50%;
			left: 50%;
			transform: translate(-50%, -50%);
			width: 100%;
			height: 52%;

			img {
				width: 100%;
				height: 100%;
				animation: error-num 0.6s ease;
			}
		}

		.login-left-waves {
			position: absolute;
			top: 0;
			right: -100px;
		}
	}

	.login-right {
		width: 700px;

		.login-right-warp {
			border-radius: 3px;
			width: 500px;
			height: 500px;
			position: relative;
			overflow: hidden;

			.login-right-warp-one,
			.login-right-warp-two {
				position: absolute;
				display: block;
				width: inherit;
				height: inherit;
				border: 1px solid var(--el-color-primary-light-3);
				background: var(--el-color-white);
				border-radius: 3px;
				transition: all 0.3s ease;
			}

			.login-right-warp-one {
				top: 13px;
				left: 13px;
				right: 13px;
				bottom: 13px;
				opacity: 0.5;
				z-index: 1;
			}
			.login-right-warp-two {
				top: 26px;
				left: 26px;
				right: 26px;
				bottom: 26px;
				opacity: 0.2;
				z-index: 0;
			}
			.login-right-warp-mian {
				position: absolute;
				top: 0;
				left: 0;
				right: 0;
				bottom: 0;
				background: var(--el-color-white);
				z-index: 2;
				padding: 50px;
				display: flex;
				flex-direction: column;
				justify-content: center;

				.login-right-warp-main-title {
					margin-bottom: 30px;

					span:first-child {
						font-size: 24px;
						font-weight: 700;
						color: var(--el-text-color-primary);
					}
					span:last-child {
						font-size: 14px;
						color: var(--el-text-color-secondary);
						line-height: 32px;
					}
				}
			}
		}
	}

	.login-authorization {
		position: fixed;
		left: 0;
		right: 0;
		bottom: 18px;
		text-align: center;
		color: var(--el-text-color-secondary);
		font-size: 12px;
	}
}

.loginBg {
	object-fit: cover;
}
</style>
