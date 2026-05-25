# -*- coding: utf-8 -*-
"""
登录链路基础接口测试
覆盖场景：
- 用户名/邮箱/手机号登录成功
- 验证码缺失/错误（开启验证码时）
- 连续输错密码导致账号锁定
- 已锁定账号再次登录
- 登录成功返回关键字段（token、用户信息、角色信息、部门信息等）
"""
import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "application.settings")
django.setup()

from unittest.mock import patch

from django.test import TestCase, override_settings
from django.contrib.auth.hashers import make_password

from dvadmin.system.models import Users, Dept, Role


def _make_password(raw):
    """Users.set_password 使用 MD5 包装，测试需保持一致"""
    import hashlib
    return hashlib.md5(raw.encode("utf-8")).hexdigest()


class BaseLoginTest(TestCase):
    """登录测试基类：负责准备测试数据"""

    @classmethod
    def setUpTestData(cls):
        # 创建部门
        cls.dept = Dept.objects.create(name="测试部门")
        # 创建角色
        cls.role = Role.objects.create(name="测试角色", key="test_role")
        # 创建测试用户（密码: Test@1234）
        cls.user = Users.objects.create(
            username="testuser",
            name="测试用户",
            email="testuser@example.com",
            mobile="13800138000",
            dept=cls.dept,
            is_active=True,
        )
        cls.user.set_password("Test@1234")
        cls.user.save()
        cls.user.role.add(cls.role)

        # 创建仅用于锁定测试的用户
        cls.lock_user = Users.objects.create(
            username="lockuser",
            name="锁定用户",
            email="lockuser@example.com",
            mobile="13900139000",
            is_active=True,
        )
        cls.lock_user.set_password("Test@1234")
        cls.lock_user.save()

    def _login_payload(self, identifier, password, captcha=None, captcha_key=None):
        """构造登录请求体"""
        data = {
            "username": identifier,
            "password": password,
        }
        if captcha is not None:
            data["captcha"] = captcha
        if captcha_key is not None:
            data["captchaKey"] = captcha_key
        return data


# ============================================================
# 一、主成功路径：用户名 / 邮箱 / 手机号登录
# ============================================================
class TestLoginSuccess(BaseLoginTest):
    """验证三种登录标识均可成功登录，且返回关键字段"""

    def _assert_login_success(self, response, user):
        """公共断言：登录成功返回体结构"""
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["code"], 2000)
        self.assertIn("data", body)
        data = body["data"]
        # token 相关
        self.assertIn("access", data)
        self.assertIn("refresh", data)
        # 用户信息
        self.assertEqual(data["userId"], user.id)
        self.assertEqual(data["username"], user.username)
        self.assertEqual(data["name"], user.name)
        # 部门信息
        self.assertIn("dept_info", data)
        self.assertEqual(data["dept_info"]["dept_id"], user.dept.id)
        self.assertEqual(data["dept_info"]["dept_name"], user.dept.name)
        # 角色信息
        self.assertIn("role_info", data)
        role_keys = [r["key"] for r in data["role_info"]]
        self.assertIn("test_role", role_keys)

    def test_login_by_username(self):
        """使用用户名登录成功"""
        resp = self.client.post(
            "/api/login/",
            data=self._login_payload("testuser", "Test@1234"),
            content_type="application/json",
        )
        self._assert_login_success(resp, self.user)

    def test_login_by_email(self):
        """使用邮箱登录成功"""
        resp = self.client.post(
            "/api/login/",
            data=self._login_payload("testuser@example.com", "Test@1234"),
            content_type="application/json",
        )
        self._assert_login_success(resp, self.user)

    def test_login_by_mobile(self):
        """使用手机号登录成功"""
        resp = self.client.post(
            "/api/login/",
            data=self._login_payload("13800138000", "Test@1234"),
            content_type="application/json",
        )
        self._assert_login_success(resp, self.user)


# ============================================================
# 二、验证码相关（开启验证码时）
# ============================================================
class TestLoginWithCaptcha(BaseLoginTest):
    """验证码开启场景下的登录校验"""

    @patch("dvadmin.system.views.login.dispatch.get_system_config_values")
    def test_captcha_missing_when_enabled(self, mock_config):
        """开启验证码时，不传验证码应返回错误"""
        mock_config.return_value = True
        resp = self.client.post(
            "/api/login/",
            data=self._login_payload("testuser", "Test@1234"),
            content_type="application/json",
        )
        body = resp.json()
        # 验证码缺失应返回错误（非 2000）
        self.assertNotEqual(body.get("code"), 2000)
        self.assertIn("验证码", body.get("msg", ""))

    @patch("dvadmin.system.views.login.dispatch.get_system_config_values")
    def test_captcha_wrong_when_enabled(self, mock_config):
        """开启验证码时，验证码错误应返回错误"""
        mock_config.return_value = True
        resp = self.client.post(
            "/api/login/",
            data=self._login_payload("testuser", "Test@1234", captcha="WRONG", captcha_key=999999),
            content_type="application/json",
        )
        body = resp.json()
        self.assertNotEqual(body.get("code"), 2000)
        self.assertIn("验证码", body.get("msg", ""))


# ============================================================
# 三、账号锁定相关
# ============================================================
class TestAccountLock(BaseLoginTest):
    """连续输错密码导致账号锁定及锁定后登录"""

    def test_account_locked_after_max_retries(self):
        """连续输错密码达到 5 次后，账号 is_active 变为 False"""
        for _ in range(5):
            self.client.post(
                "/api/login/",
                data=self._login_payload("lockuser", "WrongPassword"),
                content_type="application/json",
            )
        # 刷新用户状态
        self.lock_user.refresh_from_db()
        self.assertFalse(self.lock_user.is_active)

    def test_locked_account_cannot_login(self):
        """已锁定账号再次登录应返回账号锁定提示"""
        # 先手动锁定账号（模拟已被锁定）
        self.lock_user.is_active = False
        self.lock_user.save()

        resp = self.client.post(
            "/api/login/",
            data=self._login_payload("lockuser", "Test@1234"),
            content_type="application/json",
        )
        body = resp.json()
        self.assertNotEqual(body.get("code"), 2000)
        self.assertIn("锁定", body.get("msg", ""))


# ============================================================
# 四、其他失败场景
# ============================================================
class TestLoginFailure(BaseLoginTest):
    """其他失败分支"""

    def test_user_not_exists(self):
        """使用不存在的账号登录应返回账号不存在"""
        resp = self.client.post(
            "/api/login/",
            data=self._login_payload("nonexistent_user", "Test@1234"),
            content_type="application/json",
        )
        body = resp.json()
        self.assertNotEqual(body.get("code"), 2000)
        self.assertIn("不存在", body.get("msg", ""))

    def test_wrong_password_returns_remaining_retries(self):
        """密码错误时，返回剩余重试次数提示"""
        resp = self.client.post(
            "/api/login/",
            data=self._login_payload("testuser", "WrongPassword"),
            content_type="application/json",
        )
        body = resp.json()
        self.assertNotEqual(body.get("code"), 2000)
        # 第一次错误应提示剩余 4 次
        self.assertIn("重试", body.get("msg", ""))
        self.assertIn("4", body.get("msg", ""))
