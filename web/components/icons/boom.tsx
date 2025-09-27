import * as React from "react";
import { SVGProps } from "react";
const BoomIcon = (props: SVGProps<SVGSVGElement>) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={20}
    height={20}
    viewBox="0 0 20 20"
    fill="none"
    {...props}
  >
    <path
      stroke="currentColor"
      strokeWidth={1.667}
      d="m10 2.5 1.722 3.343 3.581-1.146-1.146 3.58L17.5 10l-3.342 1.722 2.553 4.989-4.989-2.553L10 17.5l-1.722-3.342-3.581 1.145 1.146-3.58L2.5 10l3.343-1.722-2.554-4.989 4.989 2.554L10 2.5Z"
    />
  </svg>
);
export default BoomIcon;
