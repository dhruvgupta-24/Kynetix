export type MealItem = {
    type: "roti" | "dal" | "paneer" | "sabzi" | "rice";
    quantity: number;
    unit?: "S" | "M" | "ladle";
    rotiSubtype?: "dry" | "normal" | "unknown";
};
