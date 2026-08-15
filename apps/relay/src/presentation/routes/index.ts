/**
 * Routes Module
 * Exports all route handlers
 */

export {
  handleWebSocketRoute,
  handleShortcutCommandRoute,
} from './websocket.route';
export { handleStatusRoute } from './status.route';
export { handleDeviceListRoute } from './device.route';
export { handleAdminDeviceResetRoute } from './admin.route';
export { handleHealthRoute } from './health.route';
