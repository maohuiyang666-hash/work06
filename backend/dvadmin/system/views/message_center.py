# -*- coding: utf-8 -*-

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django_restql.fields import DynamicSerializerMethodField
from rest_framework import serializers
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated

from dvadmin.system.models import MessageCenter, Users, MessageCenterTargetUser
from dvadmin.utils.json_response import SuccessResponse, DetailResponse
from dvadmin.utils.serializers import CustomModelSerializer
from dvadmin.utils.viewset import CustomModelViewSet


def get_unread_count(user_id):
    return MessageCenterTargetUser.objects.filter(users_id=user_id, is_read=False).count()


def get_target_user_ids(target_type, target_user=None, target_dept=None, target_role=None):
    target_user_ids = target_user or []
    if target_type == 1:
        target_user_ids = Users.objects.filter(role__id__in=target_role or []).values_list('id', flat=True).distinct()
    elif target_type == 2:
        target_user_ids = Users.objects.filter(dept__id__in=target_dept or []).values_list('id', flat=True).distinct()
    elif target_type == 3:
        target_user_ids = Users.objects.values_list('id', flat=True).distinct()
    return list(dict.fromkeys(int(user_id) for user_id in target_user_ids))


class MessageCenterSerializer(CustomModelSerializer):
    """
    消息中心-序列化器
    """
    role_info = DynamicSerializerMethodField()
    user_info = DynamicSerializerMethodField()
    dept_info = DynamicSerializerMethodField()
    is_read = serializers.SerializerMethodField()

    def get_is_read(self, instance):
        user_id = self.request.user.id
        relations = MessageCenterTargetUser.objects.filter(messagecenter_id=instance.id, users_id=user_id)
        if not relations.exists():
            return False
        return not relations.filter(is_read=False).exists()

    def get_role_info(self, instance, parsed_query):
        roles = instance.target_role.all()
        from dvadmin.system.views.role import RoleSerializer
        serializer = RoleSerializer(
            roles,
            many=True,
            parsed_query=parsed_query
        )
        return serializer.data

    def get_user_info(self, instance, parsed_query):
        if instance.target_type in (1, 2, 3):
            return []
        users = instance.target_user.all()
        from dvadmin.system.views.user import UserSerializer
        serializer = UserSerializer(
            users,
            many=True,
            parsed_query=parsed_query
        )
        return serializer.data

    def get_dept_info(self, instance, parsed_query):
        dept = instance.target_dept.all()
        from dvadmin.system.views.dept import DeptSerializer
        serializer = DeptSerializer(
            dept,
            many=True,
            parsed_query=parsed_query
        )
        return serializer.data

    class Meta:
        model = MessageCenter
        fields = "__all__"
        read_only_fields = ["id"]


class MessageCenterTargetUserSerializer(CustomModelSerializer):
    """
    目标用户序列化器-序列化器
    """

    class Meta:
        model = MessageCenterTargetUser
        fields = "__all__"
        read_only_fields = ["id"]


class MessageCenterTargetUserListSerializer(CustomModelSerializer):
    """
    目标用户序列化器-序列化器
    """
    role_info = DynamicSerializerMethodField()
    user_info = DynamicSerializerMethodField()
    dept_info = DynamicSerializerMethodField()
    is_read = serializers.SerializerMethodField()

    def get_is_read(self, instance):
        user_id = self.request.user.id
        relations = MessageCenterTargetUser.objects.filter(messagecenter_id=instance.id, users_id=user_id)
        if not relations.exists():
            return False
        return not relations.filter(is_read=False).exists()

    def get_role_info(self, instance, parsed_query):
        roles = instance.target_role.all()
        from dvadmin.system.views.role import RoleSerializer
        serializer = RoleSerializer(
            roles,
            many=True,
            parsed_query=parsed_query
        )
        return serializer.data

    def get_user_info(self, instance, parsed_query):
        if instance.target_type in (1, 2, 3):
            return []
        users = instance.target_user.all()
        from dvadmin.system.views.user import UserSerializer
        serializer = UserSerializer(
            users,
            many=True,
            parsed_query=parsed_query
        )
        return serializer.data

    def get_dept_info(self, instance, parsed_query):
        dept = instance.target_dept.all()
        from dvadmin.system.views.dept import DeptSerializer
        serializer = DeptSerializer(
            dept,
            many=True,
            parsed_query=parsed_query
        )
        return serializer.data

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


def push_unread_message(user_id, content, content_type='SYSTEM'):
    websocket_push(user_id, message={
        "sender": 'system',
        "contentType": content_type,
        "content": content,
        "unread": get_unread_count(user_id)
    })


class MessageCenterCreateSerializer(CustomModelSerializer):
    """
    消息中心-新增-序列化器
    """

    def save(self, **kwargs):
        data = super().save(**kwargs)
        initial_data = self.initial_data
        target_type = int(initial_data.get('target_type', data.target_type or 0))
        users = get_target_user_ids(
            target_type=target_type,
            target_user=initial_data.get('target_user', []),
            target_dept=initial_data.get('target_dept', []),
            target_role=initial_data.get('target_role', [])
        )
        targetuser_data = []
        for user in users:
            targetuser_data.append({
                "messagecenter": data.id,
                "users": user
            })
        if targetuser_data:
            targetuser_instance = MessageCenterTargetUserSerializer(data=targetuser_data, many=True, request=self.request)
            targetuser_instance.is_valid(raise_exception=True)
            targetuser_instance.save()
        for user in users:
            push_unread_message(user, '您有一条新消息~')
        return data

    class Meta:
        model = MessageCenter
        fields = "__all__"
        read_only_fields = ["id"]


class MessageCenterViewSet(CustomModelViewSet):
    """
    消息中心接口
    list:查询
    create:新增
    update:修改
    retrieve:单例
    destroy:删除
    """
    queryset = MessageCenter.objects.order_by('create_datetime')
    serializer_class = MessageCenterSerializer
    create_serializer_class = MessageCenterCreateSerializer
    extra_filter_backends = []

    def get_queryset(self):
        if self.action == 'list':
            return MessageCenter.objects.filter(creator=self.request.user.id).all()
        return MessageCenter.objects.all()

    def retrieve(self, request, *args, **kwargs):
        pk = kwargs.get('pk')
        user_id = self.request.user.id
        unread_relations = MessageCenterTargetUser.objects.filter(users_id=user_id, messagecenter_id=pk, is_read=False)
        for relation in unread_relations:
            relation.is_read = True
            relation.save(update_fields=['is_read'])
        instance = self.get_object()
        serializer = MessageCenterTargetUserListSerializer(instance, many=False, request=request)
        push_unread_message(user_id, '您查看了一条消息~', 'TEXT')
        return DetailResponse(data=serializer.data, msg="获取成功")

    @action(methods=['GET'], detail=False, permission_classes=[IsAuthenticated])
    def get_self_receive(self, request):
        self_user_id = self.request.user.id
        queryset = MessageCenter.objects.filter(target_user__id=self_user_id).distinct().order_by('-create_datetime')
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = MessageCenterTargetUserListSerializer(page, many=True, request=request)
            return self.get_paginated_response(serializer.data)
        serializer = MessageCenterTargetUserListSerializer(queryset, many=True, request=request)
        return SuccessResponse(data=serializer.data, msg="获取成功")

    @action(methods=['GET'], detail=False, permission_classes=[IsAuthenticated])
    def get_newest_msg(self, request):
        self_user_id = self.request.user.id
        queryset = MessageCenterTargetUser.objects.filter(users_id=self_user_id).order_by('create_datetime').last()
        data = None
        if queryset:
            serializer = MessageCenterTargetUserListSerializer(queryset.messagecenter, many=False, request=request)
            data = serializer.data
        return DetailResponse(data=data, msg="获取成功")

    @action(methods=['GET'], detail=False, permission_classes=[IsAuthenticated])
    def unread_count(self, request):
        return DetailResponse(data={"unread": get_unread_count(request.user.id)}, msg="获取成功")
