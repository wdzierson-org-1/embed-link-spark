export interface PhoneFormatResult {
  displayValue: string;
  cleanValue: string;
  isValid: boolean;
}

export const formatPhoneNumber = (input: string): PhoneFormatResult => {
  // Remove all non-digit characters
  const digits = input.replace(/\D/g, '');
  
  // Handle different input scenarios
  let cleanDigits = digits;
  
  // If starts with 1, keep it. If not, prepend 1 for US
  if (digits.length > 0 && !digits.startsWith('1')) {
    cleanDigits = '1' + digits;
  }
  
  // Limit to 11 digits total (1 + 10 digit US number)
  if (cleanDigits.length > 11) {
    cleanDigits = cleanDigits.slice(0, 11);
  }
  
  // Format for display
  let displayValue = '';
  if (cleanDigits.length >= 1) {
    displayValue = '+1';
    if (cleanDigits.length > 1) {
      const phoneDigits = cleanDigits.slice(1);
      if (phoneDigits.length <= 3) {
        displayValue += ` (${phoneDigits}`;
      } else if (phoneDigits.length <= 6) {
        displayValue += ` (${phoneDigits.slice(0, 3)}) ${phoneDigits.slice(3)}`;
      } else {
        displayValue += ` (${phoneDigits.slice(0, 3)}) ${phoneDigits.slice(3, 6)}-${phoneDigits.slice(6)}`;
      }
    }
  }
  
  // Check if valid (must be exactly 11 digits starting with 1)
  const isValid = cleanDigits.length === 11 && cleanDigits.startsWith('1');
  
  return {
    displayValue: displayValue || input,
    cleanValue: cleanDigits,
    isValid
  };
};

export const formatStoredPhoneNumber = (phone: string) => {
  if (phone.length === 11 && phone.startsWith('1')) {
    const areaCode = phone.slice(1, 4);
    const exchange = phone.slice(4, 7);
    const number = phone.slice(7);
    return `+1 (${areaCode}) ${exchange}-${number}`;
  }
  return phone;
};
