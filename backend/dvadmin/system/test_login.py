from django.test import TestCase, Client
from django.urls import reverse
from unittest.mock import patch
from dvadmin.system.models import Users, Dept, Role
from datetime import datetime, timedelta
from captcha.models import CaptchaStore
from application import dispatch

class LoginTestCase(TestCase):
    def setUp(self):
        self.client = Client()
        self.password = "password123"
        
        self.dept = Dept.objects.create(name="测试部门", key="test_dept")
        self.role = Role.objects.create(name="测试角色", key="test_role")
        
        self.user = Users.objects.create_user(
            username="testuser",
            password=self.password,
            email="testuser@example.com",
            mobile="13800138000",
            name="Test User",
            dept=self.dept,
            is_active=True
        )
        self.user.role.add(self.role)
        self.login_url = "/api/login/"

    @patch("application.dispatch.get_system_config_values")
    def test_login_username_success(self, mock_get_system_config):
        mock_get_system_config.return_value = False
        response = self.client.post(self.login_url, {
            "username": "testuser",
            "password": self.password
        })
        self.assertEqual(response.status_code, 200)
        res_data = response.json()
        self.assertEqual(res_data["code"], 2000)
        self.assertEqual(res_data["msg"], "请求成功")
        self.assertIn("access", res_data["data"])
        self.assertIn("refresh", res_data["data"])
        self.assertEqual(res_data["data"]["username"], "testuser")
        self.assertEqual(res_data["data"]["dept_info"]["dept_name"], "测试部门")
        self.assertEqual(res_data["data"]["role_info"][0]["name"], "测试角色")

    @patch("application.dispatch.get_system_config_values")
    def test_login_email_success(self, mock_get_system_config):
        mock_get_system_config.return_value = False
        response = self.client.post(self.login_url, {
            "username": "testuser@example.com",
            "password": self.password
        })
        self.assertEqual(response.status_code, 200)
        res_data = response.json()
        self.assertEqual(res_data["code"], 2000)
        self.assertEqual(res_data["data"]["username"], "testuser")

    @patch("application.dispatch.get_system_config_values")
    def test_login_mobile_success(self, mock_get_system_config):
        mock_get_system_config.return_value = False
        response = self.client.post(self.login_url, {
            "username": "13800138000",
            "password": self.password
        })
        self.assertEqual(response.status_code, 200)
        res_data = response.json()
        self.assertEqual(res_data["code"], 2000)
        self.assertEqual(res_data["data"]["username"], "testuser")

    @patch("application.dispatch.get_system_config_values")
    def test_login_missing_captcha(self, mock_get_system_config):
        mock_get_system_config.return_value = True
        response = self.client.post(self.login_url, {
            "username": "testuser",
            "password": self.password
        })
        self.assertEqual(response.status_code, 200)
        res_data = response.json()
        self.assertEqual(res_data["code"], 4000)
        self.assertEqual(res_data["msg"], "验证码不能为空")

    @patch("application.dispatch.get_system_config_values")
    def test_login_invalid_captcha(self, mock_get_system_config):
        mock_get_system_config.return_value = True
        captcha = CaptchaStore.objects.create(challenge="abcd", response="abcd", hashkey="testhashkey")
        response = self.client.post(self.login_url, {
            "username": "testuser",
            "password": self.password,
            "captcha": "wrong",
            "captchaKey": captcha.id
        })
        self.assertEqual(response.status_code, 200)
        res_data = response.json()
        self.assertEqual(res_data["code"], 4000)
        self.assertEqual(res_data["msg"], "图片验证码错误")

    @patch("application.dispatch.get_system_config_values")
    def test_login_account_lockout(self, mock_get_system_config):
        mock_get_system_config.return_value = False
        for i in range(1, 6):
            response = self.client.post(self.login_url, {
                "username": "testuser",
                "password": "wrongpassword"
            })
            self.assertEqual(response.status_code, 200)
            res_data = response.json()
            self.assertEqual(res_data["code"], 4000)
            if i < 5:
                self.assertIn("账号/密码错误;重试", res_data["msg"])
            else:
                self.assertEqual(res_data["msg"], "账号已被锁定,联系管理员解锁")
        
        # Verify account is locked
        self.user.refresh_from_db()
        self.assertFalse(self.user.is_active)
        
        # Attempt to login again with locked account
        response = self.client.post(self.login_url, {
            "username": "testuser",
            "password": self.password
        })
        self.assertEqual(response.status_code, 200)
        res_data = response.json()
        self.assertEqual(res_data["code"], 4000)
        self.assertEqual(res_data["msg"], "账号已被锁定,联系管理员解锁")
