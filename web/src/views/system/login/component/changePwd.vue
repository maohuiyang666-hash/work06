<template>
	<el-form ref="formRef" size="large" class="login-content-form" :model="state.ruleForm" :rules="rules"
		@keyup.enter="loginClick">
		<el-form-item class="login-animation1" prop="username">
			<el-input type="text" :placeholder="$t('message.account.accountPlaceholder1')" readonly
				v-model="ruleForm.username" clearable autocomplete="off">
				<template #prefix>
					<el-icon class="el-input__icon"><ele-User /></el-icon>
				</template>
			</el-input>
		</el-form-item>
		<el-form-item class="login-animation2" prop="password">
			<el-input :type="isShowPassword ? 'text' : 'password'"
				:placeholder="$t('message.account.accountPlaceholder4')" v-model="ruleForm.password">
				<template #prefix>
					<el-icon class="el-input__icon"><ele-Unlock /></el-icon>
				</template>
				<template #suffix>
					<i class="iconfont el-input__icon login-content-password"
						:class="isShowPassword ? 'icon-yincangmima' : 'icon-xianshimima'"
						@click="isShowPassword = !isShowPassword">
					</i>
				</template>
			</el-input>
		</el-form-item>
		<el-form-item class="login-animation3" prop="password_regain">
			<el-input :type="isShowPassword ? 'text' : 'password'"
				:placeholder="$t('message.account.accountPlaceholder5')" v-model="ruleForm.password_regain">
				<template #prefix>
					<el-icon class="el-input__icon"><ele-Unlock /></el-icon>
				</template>
				<template #suffix>
					<i class="iconfont el-input__icon login-content-password"
						:class="isShowPassword ? 'icon-yincangmima' : 'icon-xianshimima'"
						@click="isShowPassword = !isShowPassword">
					</i>
				</template>
			</el-input>
		</el-form-item>
		<el-form-item class="login-animation4">
			<el-button type="primary" class="login-content-submit" round @click="loginClick" :loading="loading.signIn">
				<span>{{ $t('message.account.accountBtnText') }}</span>
			</el-button>
		</el-form-item>
	</el-form>
	<div style="text-align: center" v-if="showApply()">
		<el-button class="login-content-apply" link type="primary" plain round @click="applyBtnClick">
			<span>申请试用</span>
		</el-button>
	</div>
</template>

<script lang="ts">
import { toRefs, reactive, defineComponent, computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ElMessage, FormRules } from 'element-plus';
import { useI18n } from 'vue-i18n';
import Cookies from 'js-cookie';
import { storeToRefs } from 'pinia';
import { useThemeConfig } from '/@/stores/themeConfig';
import { initFrontEndControlRoutes } from '/@/router/frontEnd';
import { initBackEndControlRoutes } from '/@/router/backEnd';
import { formatAxis } from '/@/utils/formatTime';
import { NextLoading } from '/@/utils/loading';
import * as loginApi from '/@/views/system/login/api';
import { DictionaryStore } from '/@/stores/dictionary';
import { SystemConfigStore } from '/@/stores/systemConfig';
import { Md5 } from 'ts-md5';
import { errorMessage } from '/@/utils/message';
import { getBaseURL } from '/@/utils/baseUrl';

export default defineComponent({
	name: 'changePwd',
	setup() {
		const { t } = useI18n();
		const storesThemeConfig = useThemeConfig();
		const { themeConfig } = storeToRefs(storesThemeConfig);
		const route = useRoute();
		const router = useRouter();
		const state = reactive({
			isShowPassword: false,
			ruleForm: {
				username: '',
				password: '',
				password_regain: '',
			},
			loading: {
				signIn: false,
			},
		});

		const validatePass = (rule, value, callback) => {
			const pwdRegex = new RegExp('(?=.*[0-9])(?=.*[a-zA-Z]).{8,30}');
			if (value === '') {
				callback(new Error('请输入密码'));
			} else if (!pwdRegex.test(value)) {
				callback(new Error('您的密码复杂度太低(密码中必须包含字母、数字)'));
			} else {
				if (state.ruleForm.password !== '') {
					formRef.value.validateField('password');
				}
				callback();
			}
		};
		const validatePass2 = (rule, value, callback) => {
			if (value === '') {
				callback(new Error('请再次输入密码'));
			} else if (value !== state.ruleForm.password) {
				callback(new Error('两次输入密码不一致!'));
			} else {
				callback();
			}
		};

		const rules = reactive<FormRules>({
			username: [{ required: true, message: '请填写账号', trigger: 'blur' }],
			password: [
				{ required: true, message: '请填写密码', trigger: 'blur' },
				{ validator: validatePass, trigger: 'blur' },
			],
			password_regain: [
				{ required: true, message: '请填写密码', trigger: 'blur' },
				{ validator: validatePass2, trigger: 'blur' },
			],
		});
		const formRef = ref();
		const currentTime = computed(() => {
			return formatAxis(new Date());
		});

		const applyBtnClick = async () => {
			window.open(getBaseURL('/api/system/apply_for_trial/'));
		};
		const getRedirectQuery = () => {
			const params = route.query?.params;
			if (!params || typeof params !== 'string') return undefined;
			try {
				const parsedParams = JSON.parse(params);
				return Object.keys(parsedParams || {}).length > 0 ? parsedParams : undefined;
			} catch (error) {
				return undefined;
			}
		};
		const redirectAfterLogin = async () => {
			const redirectPath = typeof route.query?.redirect === 'string' ? route.query.redirect : '';
			if (redirectPath && redirectPath !== '/login') {
				await router.push({
					path: redirectPath,
					query: getRedirectQuery(),
				});
				return;
			}
			await router.push('/');
		};
		const initLoginRoutes = async () => {
			if (!themeConfig.value.isRequestRoutes) {
				await initFrontEndControlRoutes();
				return;
			}
			await initBackEndControlRoutes();
		};
		const loginClick = async () => {
			if (!formRef.value) return;
			const valid = await formRef.value.validate().then(() => true).catch(() => false);
			if (!valid) {
				errorMessage('请填写登录信息');
				return;
			}
			state.loading.signIn = true;
			try {
				const res: any = await loginApi.loginChangePwd({
					...state.ruleForm,
					password: Md5.hashStr(state.ruleForm.password),
					password_regain: Md5.hashStr(state.ruleForm.password_regain),
				});
				if (res.code !== 2000) return;
				await initLoginRoutes();
				await loginSuccess();
			} catch (error) {
				errorMessage('登录失败');
			} finally {
				state.loading.signIn = false;
			}
		};

		const loginSuccess = async () => {
			DictionaryStore().getSystemDictionarys();
			const currentTimeInfo = currentTime.value;
			NextLoading.start();
			await redirectAfterLogin();
			const signInText = t('message.signInText');
			ElMessage.success(`${currentTimeInfo}，${signInText}`);
		};
		onMounted(() => {
			state.ruleForm.username = Cookies.get('username');
			SystemConfigStore().getSystemConfigs();
		});
		const showApply = () => {
			return window.location.href.indexOf('public') != -1;
		};

		return {
			loginClick,
			loginSuccess,
			state,
			formRef,
			rules,
			applyBtnClick,
			showApply,
			...toRefs(state),
		};
	},
});
</script>

<style scoped lang="scss">
.login-content-form {
	margin-top: 20px;

	:deep(.el-input__wrapper) {
		border-radius: 8px !important;
	}
	:deep(.el-input__inner) {
		font-size: 12px !important;
	}

	@for $i from 1 through 5 {
		.login-animation#{$i} {
			opacity: 0;
			animation-name: error-num;
			animation-duration: 0.5s;
			animation-fill-mode: forwards;
			animation-delay: calc($i/10) + s;
		}
	}

	.login-content-password {
		display: inline-block;
		width: 20px;
		cursor: pointer;

		&:hover {
			color: #909399;
		}
	}

	.login-content-captcha {
		width: 100%;
		padding: 0;
		font-weight: bold;
		letter-spacing: 5px;
		border-radius: 8px !important;
	}

	.login-content-submit {
		width: 100%;
		letter-spacing: 2px;
		font-weight: 800;
		margin-top: 15px;
		border-radius: 8px;
	}
}
</style>
