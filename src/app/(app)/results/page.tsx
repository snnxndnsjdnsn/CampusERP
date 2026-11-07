import { redirect } from 'next/navigation';

/** /results is the nav entry point (module 10); the grades screen lives at /results/grades. */
export default function ResultsIndex() {
  redirect('/results/grades');
}
