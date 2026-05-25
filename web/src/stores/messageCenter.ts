import {defineStore} from "pinia";
import { Session } from '/@/utils/storage';
/**
 * 消息中心
 */
export const messageCenterStore = defineStore('messageCenter', {
    state: () => ({
        // 未读消息
        unread: Session.get('messageUnread') || 0
    }),
    actions: {
        async setUnread (number: any) {
          this.unread = Number(number) || 0;
          Session.set('messageUnread', this.unread);
        }
    },
});
