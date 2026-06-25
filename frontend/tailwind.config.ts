import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        ritual: {
          50: '#f0f0ff',
          100: '#e0e0ff',
          200: '#c0c0ff',
          300: '#a0a0ff',
          400: '#8080ff',
          500: '#6c63ff',
          600: '#5a52d5',
          700: '#4840ab',
          800: '#362f81',
          900: '#241e57',
          950: '#12102d',
        },
      },
    },
  },
  plugins: [],
};

export default config;
