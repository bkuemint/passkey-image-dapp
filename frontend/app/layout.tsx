import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Passkey Image dApp',
  description: 'Generate AI images on Ritual Chain with passkey login',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen flex flex-col items-center justify-start p-4 sm:p-8">
        {children}
      </body>
    </html>
  );
}
