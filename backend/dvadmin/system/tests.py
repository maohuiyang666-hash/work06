import os
import django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "application.settings")
django.setup()

from django.test import TestCase, Client
from django.urls import reverse
from captcha.models import CaptchaStore
from unittest.mock import patch
from dvadmin.system.models import Users, Role, Dept, SystemConfig


class LoginApiTestCase(TestCase):
    def setUp(self):
        self.client = Client()
        self.login_url = reverse('token_obtain_pair')
        
        self.dept = Dept.objects.create(
            name="测试部门",
            key="test_dept",
            sort=1
        )
        
        self.role = Role.objects.create(
            name="测试角色",
            key="test_role",
            sort=1
        )
        
        self.user = Users.objects.create(
            username="testuser",
            email="test@example.com",
            mobile="13800138000",
            name="测试用户",
            dept=self.dept,
            login_error_count=0,
            is_active=True
        )
        self.user.set_password("test123456")
        self.user.role.add(self.role)
        self.user.save()
        
        self.captcha_config = SystemConfig.objects.create(
            key="base.captcha_state",
            value=False,
            title="验证码开关",
            sort=1
        )
    
    def _set_captcha_state(self, enabled):
        self.captcha_config.value = enabled
        self.captcha_config.save()
    
    def _create_valid_captcha(self):
        captcha = CaptchaStore.objects.create(
            challenge="1+1",
            response="2"
        )
        return captcha
    
    def test_login_with_username_success(self):
        self._set_captcha_state(False)
        
        response = self.client.post(
            self.login_url,
            {
                'username': 'testuser',
                'password': 'test123456'
            },
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['code'], 2000)
        self.assertEqual(response.data['msg'], '请求成功')
        self.assertIn('data', response.data)
        self.assertIn('access', response.data['data'])
        self.assertIn('refresh', response.data['data'])
        self.assertEqual(response.data['data']['username'], 'testuser')
    
    def test_login_with_email_success(self):
        self._set_captcha_state(False)
        
        response = self.client.post(
            self.login_url,
            {
                'username': 'test@example.com',
                'password': 'test123456'
            },
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['code'], 2000)
        self.assertIn('access', response.data['data'])
    
    def test_login_with_mobile_success(self):
        self._set_captcha_state(False)
        
        response = self.client.post(
            self.login_url,
            {
                'username': '13800138000',
                'password': 'test123456'
            },
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['code'], 2000)
        self.assertIn('access', response.data['data'])
    
    def test_login_missing_captcha_when_enabled(self):
        self._set_captcha_state(True)
        
        response = self.client.post(
            self.login_url,
            {
                'username': 'testuser',
                'password': 'test123456'
            },
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 400)
        self.assertIn('验证码不能为空', str(response.data))
    
    def test_login_wrong_captcha(self):
        self._set_captcha_state(True)
        captcha = self._create_valid_captcha()
        
        response = self.client.post(
            self.login_url,
            {
                'username': 'testuser',
                'password': 'test123456',
                'captcha': '3',
                'captchaKey': captcha.id
            },
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 400)
        self.assertIn('图片验证码错误', str(response.data))
    
    def test_login_correct_captcha(self):
        self._set_captcha_state(True)
        captcha = self._create_valid_captcha()
        
        response = self.client.post(
            self.login_url,
            {
                'username': 'testuser',
                'password': 'test123456',
                'captcha': '2',
                'captchaKey': captcha.id
            },
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['code'], 2000)
    
    def test_login_wrong_password_increments_error_count(self):
        self._set_captcha_state(False)
        
        response = self.client.post(
            self.login_url,
            {
                'username': 'testuser',
                'password': 'wrongpassword'
            },
            content_type='application/json'
        )
        
        self.user.refresh_from_db()
        self.assertEqual(self.user.login_error_count, 1)
        self.assertIn('账号/密码错误', str(response.data))
    
    def test_account_lock_after_five_failed_attempts(self):
        self._set_captcha_state(False)
        
        for i in range(4):
            self.client.post(
                self.login_url,
                {
                    'username': 'testuser',
                    'password': 'wrongpassword'
                },
                content_type='application/json'
            )
        
        self.user.refresh_from_db()
        self.assertEqual(self.user.login_error_count, 4)
        self.assertTrue(self.user.is_active)
        
        response = self.client.post(
            self.login_url,
            {
                'username': 'testuser',
                'password': 'wrongpassword'
            },
            content_type='application/json'
        )
        
        self.user.refresh_from_db()
        self.assertEqual(self.user.login_error_count, 5)
        self.assertFalse(self.user.is_active)
        self.assertIn('账号已被锁定', str(response.data))
    
    def test_locked_account_cannot_login(self):
        self._set_captcha_state(False)
        
        self.user.is_active = False
        self.user.save()
        
        response = self.client.post(
            self.login_url,
            {
                'username': 'testuser',
                'password': 'test123456'
            },
            content_type='application/json'
        )
        
        self.assertIn('账号已被锁定', str(response.data))
    
    def test_login_success_resets_error_count(self):
        self._set_captcha_state(False)
        
        self.user.login_error_count = 3
        self.user.save()
        
        self.client.post(
            self.login_url,
            {
                'username': 'testuser',
                'password': 'test123456'
            },
            content_type='application/json'
        )
        
        self.user.refresh_from_db()
        self.assertEqual(self.user.login_error_count, 0)
    
    def test_login_response_contains_required_fields(self):
        self._set_captcha_state(False)
        
        response = self.client.post(
            self.login_url,
            {
                'username': 'testuser',
                'password': 'test123456'
            },
            content_type='application/json'
        )
        
        data = response.data['data']
        
        self.assertIn('access', data)
        self.assertIn('refresh', data)
        self.assertIn('username', data)
        self.assertIn('name', data)
        self.assertIn('userId', data)
        self.assertIn('avatar', data)
        self.assertIn('user_type', data)
        self.assertIn('pwd_change_count', data)
        self.assertIn('dept_info', data)
        self.assertIn('role_info', data)
        
        self.assertEqual(data['dept_info']['dept_id'], self.dept.id)
        self.assertEqual(data['dept_info']['dept_name'], '测试部门')
