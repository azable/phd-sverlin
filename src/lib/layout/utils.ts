export const randomUUID = (): string => {
  return crypto.randomUUID().slice(0, 8);
};
