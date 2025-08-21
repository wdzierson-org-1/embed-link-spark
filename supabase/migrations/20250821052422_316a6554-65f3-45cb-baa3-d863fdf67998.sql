-- Add foreign key relationship between items and user_profiles
ALTER TABLE items 
ADD CONSTRAINT items_user_id_fkey 
FOREIGN KEY (user_id) 
REFERENCES user_profiles(id) 
ON DELETE CASCADE;