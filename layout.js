export const metadata = {
  title: 'Background Catalog API',
  description: 'Vercel API route for Roblox background catalog data',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
