import { DrizzleD1Database } from "drizzle-orm/d1";

export type Env = {
  Bindings: {
    DB: D1Database;
    JWT_SECRET: string;
    SUPER_ADMIN_PASSWORD: string;
    DEFAULT_SCOUT_PASSWORD: string;
  };
  Variables: {
    db: DrizzleD1Database;
    jwtPayload: JwtPayload;
  };
};

export type JwtPayload = {
  sub: string;
  scout_id: string;
  full_name: string;
  role: "admin" | "scout";
  iat: number;
  exp: number;
};