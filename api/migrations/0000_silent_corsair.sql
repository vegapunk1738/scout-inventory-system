CREATE TABLE `buckets` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`barcode` text NOT NULL,
	`created_at` text NOT NULL,
	`created_by` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `buckets_barcode_unique` ON `buckets` (`barcode`);--> statement-breakpoint
CREATE TABLE `item_types` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`emoji` text NOT NULL,
	`bucket_id` text NOT NULL,
	`max_quantity` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE TABLE `transaction_items` (
	`id` text PRIMARY KEY NOT NULL,
	`transaction_id` text NOT NULL,
	`bucket_id` text NOT NULL,
	`item_type_id` text NOT NULL,
	`quantity` integer NOT NULL,
	`direction` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `transactions` (
	`id` text PRIMARY KEY NOT NULL,
	`type` text NOT NULL,
	`user_id` text NOT NULL,
	`created_at` text NOT NULL,
	`idempotency_key` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `transactions_idempotency_key_unique` ON `transactions` (`idempotency_key`);--> statement-breakpoint
CREATE TABLE `users` (
	`id` text PRIMARY KEY NOT NULL,
	`scout_id` text NOT NULL,
	`full_name` text NOT NULL,
	`password_hash` text NOT NULL,
	`role` text DEFAULT 'scout' NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `users_scout_id_unique` ON `users` (`scout_id`);