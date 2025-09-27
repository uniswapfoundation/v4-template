import * as React from "react";
import { SVGProps } from "react";
const BellIcon = (props: SVGProps<SVGSVGElement>) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={24}
    height={24}
    viewBox="0 0 24 24"
    fill="none"
    {...props}
  >
    <path
      stroke="currentColor"
      strokeLinecap="square"
      strokeWidth={2}
      d="M8.031 17.5a4 4 0 0 0 7.938 0M4 17h16v-1l-1.5-3-.2-4.007a6.307 6.307 0 0 0-12.6 0L5.5 13 4 16v1Z"
    />
  </svg>
);
export default BellIcon;
