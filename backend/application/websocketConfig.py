# -*- coding: utf-8 -*-
import urllib

from asgiref.sync import async_to_sync
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer
import json

from channels.layers import get_channel_layer
from jwt import InvalidSignatureError
from rest_framework.request import Request

from application import settings
from dvadmin.system.models import MessageCenter
from dvadmin.system.views.message_center import MessageCenterTargetUserSerializer, get_target_user_ids, get_unread_count
from dvadmin.utils.serializers import CustomModelSerializer

send_dict = {}


def set_message(sender, msg_type, msg, unread=0):
    text = {
        'sender': sender,
        'contentType': msg_type,
        'content': msg,
        'unread': unread
    }
    return text


@database_sync_to_async
def _get_message_center_instance(message_id):
    message_center = MessageCenter.objects.filter(id=message_id).values_list('target_user', flat=True).distinct()
    if message_center:
        return message_center
    return []


@database_sync_to_async
def _get_message_unread(user_id):
    count = get_unread_count(user_id)
    return count or 0


def request_data(scope):
    query_string = scope.get('query_string', b'').decode('utf-8')
    qs = urllib.parse.parse_qs(query_string)
    return qs


class DvadminWebSocket(AsyncJsonWebsocketConsumer):
    async def connect(self):
        try:
            import jwt
            self.service_uid = self.scope["url_route"]["kwargs"]["service_uid"]
            decoded_result = jwt.decode(self.service_uid, settings.SECRET_KEY, algorithms=["HS256"])
            if decoded_result:
                self.user_id = decoded_result.get('user_id')
                self.chat_group_name = "user_" + str(self.user_id)
                await self.channel_layer.group_add(
                    self.chat_group_name,
                    self.channel_name
                )
                await self.accept()
                unread_count = await _get_message_unread(self.user_id)
                if unread_count == 0:
                    await self.send_json(set_message('system', 'SYSTEM', '您已上线'))
                else:
                    await self.send_json(
                        set_message('system', 'SYSTEM', "请查看您的未读消息~", unread=unread_count))
        except InvalidSignatureError:
            await self.disconnect(None)

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.chat_group_name, self.channel_name)
        print("连接关闭")
        try:
            await self.close(close_code)
        except Exception:
            pass


class MegCenter(DvadminWebSocket):
    """
    消息中心
    """

    async def receive(self, text_data):
        text_data_json = json.loads(text_data)
        message_id = text_data_json.get('message_id', None)
        user_list = await _get_message_center_instance(message_id)
        for send_user in user_list:
            await self.channel_layer.group_send(
                "user_" + str(send_user),
                {'type': 'push.message', 'json': text_data_json}
            )

    async def push_message(self, event):
        message = event['json']
        await self.send(text_data=json.dumps(message))


class MessageCreateSerializer(CustomModelSerializer):
    """
    消息中心-新增-序列化器
    """
    class Meta:
        model = MessageCenter
        fields = "__all__"
        read_only_fields = ["id"]


def websocket_push(user_id, message):
    username = "user_" + str(user_id)
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        username,
        {
            "type": "push.message",
            "json": message
        }
    )


def create_message_push(title: str, content: str, target_type: int = 0, target_user: list = None, target_dept=None,
                        target_role=None, message: dict = None, request=Request):
    if message is None:
        message = {"contentType": "INFO", "content": None}
    if target_role is None:
        target_role = []
    if target_dept is None:
        target_dept = []
    data = {
        "title": title,
        "content": content,
        "target_type": target_type,
        "target_user": target_user,
        "target_dept": target_dept,
        "target_role": target_role
    }
    message_center_instance = MessageCreateSerializer(data=data, request=request)
    message_center_instance.is_valid(raise_exception=True)
    message_center_instance.save()
    users = get_target_user_ids(
        target_type=target_type,
        target_user=target_user or [],
        target_dept=target_dept,
        target_role=target_role
    )
    targetuser_data = []
    for user in users:
        targetuser_data.append({
            "messagecenter": message_center_instance.instance.id,
            "users": user
        })
    if targetuser_data:
        targetuser_instance = MessageCenterTargetUserSerializer(data=targetuser_data, many=True, request=request)
        targetuser_instance.is_valid(raise_exception=True)
        targetuser_instance.save()
    for user in users:
        websocket_push(user, message={**message, 'unread': get_unread_count(user)})
