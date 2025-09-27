import * as React from "react";
import { SVGProps } from "react";
const GearIcon = (props: SVGProps<SVGSVGElement>) => (
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
      strokeLinecap="square"
      strokeWidth={1.667}
      d="m10 2.5 6.666 3.75v7.5L10 17.5l-6.667-3.75v-7.5L10 2.5Z"
    />
    <path
      stroke="currentColor"
      strokeLinecap="square"
      strokeWidth={1.667}
      d="M12.5 10a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0Z"
    />
  </svg>
);
export default GearIcon;
