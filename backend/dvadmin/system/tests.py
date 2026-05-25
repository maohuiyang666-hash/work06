from unittest.mock import patch

from captcha.views import CaptchaStore
from django.test import TestCase
from rest_framework.test import APIClient

from dvadmin.system.models import Dept, Role, Users


class LoginViewTests(TestCase):
    login_url = "/api/login/"
    password = "Login123456"
    wrong_password = "Login123456-wrong"

    @classmethod
    def setUpTestData(cls):
        cls.role = Role.objects.create(name="登录测试角色", key="login-test-role")
        cls.dept = Dept.objects.create(name="登录测试部门", key="login-test-dept")
        cls.user = Users.objects.create(
            username="login_user",
            email="login_user@example.com",
            mobile="13800138000",
            name="登录测试用户",
            avatar="/media/avatar.png",
            dept=cls.dept,
            current_role=cls.role,
        )
        cls.user.set_password(cls.password)
        cls.user.save()
        cls.user.role.add(cls.role)

    def setUp(self):
        self.client = APIClient()

    def login(self, username, password=None, captcha_enabled=False, extra_payload=None):
        payload = {
            "username": username,
            "password": password or self.password,
        }
        if extra_payload:
            payload.update(extra_payload)
        with patch("dvadmin.system.views.login.dispatch.get_system_config_values", return_value=captcha_enabled), patch(
            "dvadmin.system.views.login.save_login_log"
        ):
            return self.client.post(self.login_url, payload, format="json")

    def create_captcha(self):
        hashkey = CaptchaStore.generate_key()
        return CaptchaStore.objects.get(hashkey=hashkey)

    def assert_business_success(self, response):
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["code"], 2000)
        self.assertEqual(payload["msg"], "请求成功")
        self.assertIsInstance(payload["data"], dict)
        return payload["data"]

    def assert_business_error(self, response, expected_msg):
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload, {"code": 4000, "data": None, "msg": expected_msg})

    def assert_login_payload(self, data):
        self.assertIn("access", data)
        self.assertIn("refresh", data)
        self.assertEqual(data["username"], self.user.username)
        self.assertEqual(data["name"], self.user.name)
        self.assertEqual(data["userId"], self.user.id)
        self.assertEqual(data["avatar"], self.user.avatar)
        self.assertEqual(data["user_type"], self.user.user_type)
        self.assertEqual(data["pwd_change_count"], self.user.pwd_change_count)
        self.assertEqual(
            data["dept_info"],
            {
                "dept_id": self.dept.id,
                "dept_name": self.dept.name,
            },
        )
        self.assertEqual(
            data["role_info"],
            [{"id": self.role.id, "name": self.role.name, "key": self.role.key}],
        )

    def test_login_with_username_succeeds_and_returns_frontend_init_fields(self):
        response = self.login(self.user.username)

        data = self.assert_business_success(response)
        self.assert_login_payload(data)
        self.user.refresh_from_db()
        self.assertEqual(self.user.login_error_count, 0)

    def test_login_with_email_succeeds(self):
        response = self.login(self.user.email)

        data = self.assert_business_success(response)
        self.assertEqual(data["username"], self.user.username)
        self.assertEqual(data["userId"], self.user.id)

    def test_login_with_mobile_succeeds(self):
        response = self.login(self.user.mobile)

        data = self.assert_business_success(response)
        self.assertEqual(data["username"], self.user.username)
        self.assertEqual(data["userId"], self.user.id)

    def test_login_requires_captcha_when_enabled(self):
        response = self.login(self.user.username, captcha_enabled=True)

        self.assert_business_error(response, "验证码不能为空")

    def test_login_rejects_invalid_captcha_when_enabled(self):
        captcha = self.create_captcha()

        response = self.login(
            self.user.username,
            captcha_enabled=True,
            extra_payload={
                "captcha": "wrong-code",
                "captchaKey": captcha.id,
            },
        )

        self.assert_business_error(response, "图片验证码错误")
        self.assertFalse(CaptchaStore.objects.filter(id=captcha.id).exists())

    def test_login_locks_account_after_reaching_wrong_password_threshold(self):
        expected_messages = [
            "账号/密码错误;重试4次后将被锁定~",
            "账号/密码错误;重试3次后将被锁定~",
            "账号/密码错误;重试2次后将被锁定~",
            "账号/密码错误;重试1次后将被锁定~",
            "账号已被锁定,联系管理员解锁",
        ]

        for expected_msg in expected_messages:
            response = self.login(self.user.username, password=self.wrong_password)
            self.assert_business_error(response, expected_msg)

        self.user.refresh_from_db()
        self.assertFalse(self.user.is_active)
        self.assertEqual(self.user.login_error_count, 5)

        locked_response = self.login(self.user.username)
        self.assert_business_error(locked_response, "账号已被锁定,联系管理员解锁")
