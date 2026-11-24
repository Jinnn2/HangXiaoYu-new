// 前端只通过 HTTP 调用后端接口，不接触数据库。

export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

export async function api<T = unknown>(path: string, options: { method?: string; body?: unknown } = {}): Promise<T> {
  const res = await fetch(`/api${path}`, {
    method: options.method ?? (options.body !== undefined ? "POST" : "GET"),
    headers: options.body !== undefined ? { "Content-Type": "application/json" } : undefined,
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
    credentials: "same-origin",
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(data.detail ?? `请求失败（${res.status}）`, res.status);
  return data as T;
}

export const get = <T,>(path: string) => api<T>(path);
export const post = <T,>(path: string, body: unknown = {}) => api<T>(path, { method: "POST", body });
export const put = <T,>(path: string, body: unknown = {}) => api<T>(path, { method: "PUT", body });
export const del = <T,>(path: string) => api<T>(path, { method: "DELETE" });

export type ListingStatus = "ON_SALE" | "PAYMENT_RESERVED" | "TRADING" | "RELIST_BUFFER" | "OFF_SHELF" | "SOLD";
export type OrderStatus =
  | "PENDING_PAYMENT" | "PENDING_DELIVERY" | "PENDING_RECEIPT" | "UNDER_REVIEW"
  | "COMPLETED" | "CANCELED" | "PAYMENT_EXPIRED";

export interface Me {
  user_id: number;
  student_no: string;
  display_name: string;
  role: "USER" | "ADMIN";
  spendable_points: number;
  escrow_points: number;
  buyer_reward_points: number;
  pending_reward_points: number;
  seller_reputation: number;
  completed_sales: number;
  created_at: string;
}

export interface Category { category_id: number; name: string }

export interface Listing {
  listing_id: number;
  title: string;
  description: string;
  condition_level: number;
  original_price_points: number | null;
  current_price_points: number;
  image_url: string | null;
  status: ListingStatus;
  relist_blocked: boolean;
  created_at: string;
  updated_at: string;
  category_id: number;
  category_name: string;
  seller_id: number;
  seller_name: string;
  seller_reputation: number;
  favorite_count: number;
  last_canceled_at?: string | null;
}

export interface ListingDetail extends Listing {
  price_history: { history_id: number; price_points: number; change_type: "INITIAL" | "REPRICE"; changed_at: string }[];
  is_favorite: boolean;
  my_active_order_id: number | null;
}

export interface Order {
  order_id: number;
  listing_id: number;
  listing_title: string;
  image_url: string | null;
  category_name: string;
  buyer_id: number;
  buyer_name: string;
  seller_id: number;
  seller_name: string;
  price_snapshot_points: number;
  status: OrderStatus;
  created_at: string;
  payment_deadline_at: string;
  paid_at: string | null;
  delivered_at: string | null;
  auto_complete_at: string | null;
  completed_at: string | null;
  completion_method: "BUYER_CONFIRMED" | "AUTO" | null;
  canceled_at: string | null;
  cancel_reason: string | null;
  open_review_id: number | null;
  open_review_reason: string | null;
  server_time: string;
}

export interface OrderDetail extends Order {
  my_role: "buyer" | "seller" | "admin";
  reviews: { review_id: number; reason: string; previous_status: string; opened_at: string; decision: string | null; resolved_at: string | null }[];
  transfers: { event_type: string; occurred_at: string; delta_points: number; owner_type: string; user_id: number | null }[];
}

export interface LedgerRow {
  ledger_id: number;
  transfer_id: number;
  order_id: number | null;
  event_type: "GRANT" | "PAYMENT" | "SETTLEMENT" | "REFUND";
  occurred_at: string;
  delta_points: number;
  listing_title: string | null;
}

export interface Estimate {
  suggested_price_points: number;
  low_price_points: number;
  high_price_points: number;
  sample_count: number;
  market_ratio: number | null;
}

export interface Valuation extends Estimate {
  valuation_id: number;
  category_id: number;
  category_name: string;
  item_name: string;
  condition_level: number;
  original_price_points: number;
  created_at: string;
}
