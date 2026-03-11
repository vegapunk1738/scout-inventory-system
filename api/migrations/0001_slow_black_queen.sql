PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_item_types` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`emoji` text NOT NULL,
	`bucket_id` text NOT NULL,
	`quantity` integer DEFAULT 1 NOT NULL
);
--> statement-breakpoint
INSERT INTO `__new_item_types`("id", "name", "emoji", "bucket_id", "quantity") SELECT "id", "name", "emoji", "bucket_id", "quantity" FROM `item_types`;--> statement-breakpoint
DROP TABLE `item_types`;--> statement-breakpoint
ALTER TABLE `__new_item_types` RENAME TO `item_types`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
ALTER TABLE `transaction_items` ADD `status` text DEFAULT 'normal' NOT NULL;