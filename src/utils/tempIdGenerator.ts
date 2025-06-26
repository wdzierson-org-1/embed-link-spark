
import { v4 as uuidv4 } from 'uuid';

export const generateTempId = (): string => {
  // Generate a proper UUID format for temporary IDs
  // We'll prefix it with "temp-" and use a real UUID to avoid parsing errors
  return `temp-${uuidv4()}`;
};

export const isTempId = (id: string): boolean => {
  return id.startsWith('temp-');
};

export const validateUuid = (id: string): boolean => {
  if (isTempId(id)) {
    return false; // Temp IDs should never be used in database queries
  }
  
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(id);
};
