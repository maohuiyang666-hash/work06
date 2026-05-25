import { ElNotification as message } from 'element-plus'
import { Session } from '/@/utils/storage';
import { getWsBaseURL } from '/@/utils/baseUrl';
// @ts-ignore
import socket from '@/types/api/socket'
import { useUserInfo } from '/@/stores/userInfo';

const setSocketState = (isOpen: boolean) => {
	websocket.socket_open = isOpen
	useUserInfo().setWebSocketState(isOpen);
}

const clearHeartbeatTimer = () => {
	if (websocket.hearbeat_timer) {
		clearInterval(websocket.hearbeat_timer)
		websocket.hearbeat_timer = null
	}
}

const clearReconnectTimer = () => {
	if (websocket.reconnect_timer) {
		clearTimeout(websocket.reconnect_timer)
		websocket.reconnect_timer = null
	}
}

const websocket: socket = {
	websocket: null,
	connectURL: getWsBaseURL(),
	socket_open: false,
	hearbeat_timer: null,
	hearbeat_interval: 2 * 1000,
	is_reonnect: true,
	reconnect_count: 3,
	reconnect_current: 1,
	reconnect_timer: null,
	reconnect_interval: 5 * 1000,
	receiveMessage: null,
	init: (receiveMessage: Function | null) => {
		if (receiveMessage) {
			websocket.receiveMessage = receiveMessage
		}
		if (!('WebSocket' in window)) {
			message.warning('浏览器不支持WebSocket')
			return null
		}
		const token = Session.get('token')
		if (!token) {
			return null
		}
		if (websocket.websocket) {
			const { readyState } = websocket.websocket
			if (readyState === WebSocket.OPEN || readyState === WebSocket.CONNECTING) {
				return websocket.websocket
			}
		}
		clearReconnectTimer()
		const wsUrl = `${getWsBaseURL()}ws/${token}/`
		const currentSocket = new WebSocket(wsUrl)
		websocket.websocket = currentSocket
		currentSocket.onmessage = (e: any) => {
			if (websocket.receiveMessage) {
				websocket.receiveMessage(e)
			}
		}
		currentSocket.onclose = () => {
			if (websocket.websocket === currentSocket) {
				websocket.websocket = null
			}
			clearHeartbeatTimer()
			setSocketState(false)
			if (!websocket.is_reonnect || websocket.reconnect_timer) {
				return
			}
			websocket.reconnect_timer = setTimeout(() => {
				websocket.reconnect_timer = null
				if (websocket.reconnect_current > websocket.reconnect_count) {
					websocket.is_reonnect = false
					setSocketState(false)
					return
				}
				websocket.reconnect_current += 1
				websocket.reconnect()
			}, websocket.reconnect_interval)
		}
		currentSocket.onopen = () => {
			clearReconnectTimer()
			websocket.reconnect_current = 1
			websocket.is_reonnect = true
			setSocketState(true)
			websocket.heartbeat()
		}
		currentSocket.onerror = () => {}
		return currentSocket
	},
	heartbeat: () => {
		clearHeartbeatTimer()
		websocket.hearbeat_timer = setInterval(() => {
			const data = {
				token: Session.get('token')
			}
			websocket.send(data)
		}, websocket.hearbeat_interval)
	},
	send: (data: string, callback = null) => {
		if (websocket.websocket && websocket.websocket.readyState === WebSocket.OPEN) {
			websocket.websocket.send(JSON.stringify(data))
			// @ts-ignore
			callback && callback()
		} else {
			clearHeartbeatTimer()
			setSocketState(false)
		}
	},
	close: () => {
		websocket.is_reonnect = false
		clearReconnectTimer()
		clearHeartbeatTimer()
		if (websocket.websocket) {
			const currentSocket = websocket.websocket
			websocket.websocket = null
			currentSocket.close()
		}
		setSocketState(false)
	},
	reconnect: () => {
		if (websocket.websocket && websocket.websocket.readyState === WebSocket.OPEN) {
			return websocket.websocket
		}
		return websocket.init(websocket.receiveMessage)
	},
}
export default websocket;
